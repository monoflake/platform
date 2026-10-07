//! Postgres's own programs, run by the keeper: making, copying and rewinding a cluster, starting
//! and stopping it, and asking it things over its socket.

use crate::config::Config;
use crate::render::{self, REPLICATOR, SUPERUSER};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use std::time::Duration;
use tokio::io::AsyncWriteExt;
use tokio::process::{Child, Command};

/// Where the socket and the configuration written each start go: the container's scratch.
pub const RUN: &str = "/tmp";
/// How long a started Postgres has to accept connections, crash recovery included.
const READY_SECONDS: u64 = 600;

#[derive(Debug, thiserror::Error)]
pub enum Error {
	#[error("{program} could not be started: {source}")]
	Spawn { program: String, source: std::io::Error },
	#[error("{program} failed: {detail}")]
	Failed { program: String, detail: String },
	#[error("{path}: {source}")]
	Io { path: String, source: std::io::Error },
	#[error("Postgres exited before it accepted connections")]
	Exited,
	#[error("Postgres did not accept connections within {READY_SECONDS} seconds")]
	Slow,
}

fn io(path: &Path) -> impl FnOnce(std::io::Error) -> Error + '_ {
	move |source| Error::Io { path: path.display().to_string(), source }
}

#[derive(Debug, Clone)]
pub struct Layout {
	pub data: PathBuf,
	pub run: PathBuf,
}

impl Layout {
	pub fn new(data: PathBuf) -> Self {
		Self { data, run: PathBuf::from(RUN) }
	}

	/// Beside the data directory, where a cluster is made or copied before it is renamed into
	/// place, so one interrupted halfway is never taken for a cluster.
	fn partial(&self) -> PathBuf {
		let mut name = self.data.file_name().unwrap_or_default().to_os_string();
		name.push(".partial");
		self.data.with_file_name(name)
	}

	pub fn conf(&self) -> PathBuf {
		self.run.join("postgresql.conf")
	}

	pub fn passfile(&self) -> PathBuf {
		self.run.join("pgpass")
	}
}

/// A program with the passwords the keeper was given taken out of its environment: Postgres, its
/// archive command and WAL-G read neither, and libpq reads them from the password file.
pub fn command(program: &str) -> Command {
	let mut command = Command::new(program);
	command.env_remove("POSTGRES_PASSWORD").env_remove("REPLICATION_PASSWORD");
	command
}

/// Run to the end, its errors written to the log as they are and the last line of them carried in
/// the failure; what it printed is the answer.
pub async fn output(mut command: Command, stdin: Option<&str>) -> Result<String, Error> {
	let program = command.as_std().get_program().to_string_lossy().into_owned();
	command
		.stdin(if stdin.is_some() { Stdio::piped() } else { Stdio::null() })
		.stdout(Stdio::piped())
		.stderr(Stdio::piped());
	let mut child =
		command.spawn().map_err(|source| Error::Spawn { program: program.clone(), source })?;
	if let (Some(text), Some(mut pipe)) = (stdin, child.stdin.take()) {
		let written = pipe.write_all(text.as_bytes()).await;
		drop(pipe);
		written.map_err(|source| Error::Spawn { program: program.clone(), source })?;
	}
	let out = child
		.wait_with_output()
		.await
		.map_err(|source| Error::Spawn { program: program.clone(), source })?;
	let errors = String::from_utf8_lossy(&out.stderr);
	if !errors.trim().is_empty() {
		eprint!("{errors}");
	}
	if !out.status.success() {
		let last = errors.lines().rev().find(|line| !line.trim().is_empty()).unwrap_or("");
		return Err(Error::Failed { program, detail: format!("{}: {last}", out.status) });
	}
	Ok(String::from_utf8_lossy(&out.stdout).into_owned())
}

/// Write a file only its owner reads.
async fn private(path: &Path, content: &str) -> Result<(), Error> {
	tokio::fs::write(path, content).await.map_err(io(path))?;
	tokio::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600)).await.map_err(io(path))
}

/// The configuration, the access rules and the password file, written for this start. `follow` is
/// the primary to stream from, on a standby.
pub async fn prepare(layout: &Layout, config: &Config, follow: Option<&str>) -> Result<(), Error> {
	tokio::fs::create_dir_all(&layout.run).await.map_err(io(&layout.run))?;
	let conninfo =
		follow.map(|host| render::conninfo(host, REPLICATOR, &layout.passfile(), &config.node));
	let conf = render::postgresql_conf(&layout.data, &layout.run, conninfo.as_deref());
	private(&layout.conf(), &conf).await?;
	private(&layout.run.join("pg_hba.conf"), &render::pg_hba()).await?;
	private(&layout.run.join("pg_ident.conf"), "").await?;
	let passwords = [
		(REPLICATOR, config.replication_password.as_str()),
		(SUPERUSER, config.superuser_password.as_str()),
	];
	private(&layout.passfile(), &render::pgpass(&passwords)).await
}

/// Remove the lock a Postgres stopped uncleanly left in the cluster. It names a process in the
/// container that is gone, whose number a new container often gives to a live one, so Postgres
/// would refuse to start; and a lock in another container's namespace never protected anything.
/// Called before the keeper starts anything that reads the cluster.
pub async fn clear_stale_lock(layout: &Layout) -> Result<bool, Error> {
	let lock = layout.data.join("postmaster.pid");
	match tokio::fs::remove_file(&lock).await {
		Ok(()) => Ok(true),
		Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
		Err(error) => Err(io(&lock)(error)),
	}
}

/// Clear what an interrupted attempt left beside the data directory.
async fn clear_partial(layout: &Layout) -> Result<(), Error> {
	let partial = layout.partial();
	match tokio::fs::remove_dir_all(&partial).await {
		Err(error) if error.kind() != std::io::ErrorKind::NotFound => Err(io(&partial)(error)),
		_ => Ok(()),
	}
}

/// Move a finished cluster into place over the empty data directory, if there is one.
async fn settle(layout: &Layout) -> Result<(), Error> {
	if tokio::fs::try_exists(&layout.data).await.unwrap_or(false) {
		tokio::fs::remove_dir(&layout.data).await.map_err(io(&layout.data))?;
	}
	tokio::fs::rename(layout.partial(), &layout.data).await.map_err(io(&layout.data))
}

/// A new cluster, its superuser's password set. Data checksums are Postgres 18's default and
/// stay, since `pg_rewind` needs them. The builtin locale ties sorting to Postgres rather than to
/// the C library of whichever image restores it.
pub async fn initialize(layout: &Layout, config: &Config) -> Result<(), Error> {
	clear_partial(layout).await?;
	let pwfile = layout.run.join("initdb.pw");
	private(&pwfile, &config.superuser_password).await?;
	let mut initdb = command("initdb");
	initdb
		.arg("--pgdata")
		.arg(layout.partial())
		.args(["--username", SUPERUSER, "--auth-local=peer", "--auth-host=scram-sha-256"])
		.args(["--encoding=UTF8", "--locale=C.UTF-8", "--locale-provider=builtin"])
		.arg("--builtin-locale=C.UTF-8")
		.arg(format!("--pwfile={}", pwfile.display()));
	let made = output(initdb, None).await;
	let _ = tokio::fs::remove_file(&pwfile).await;
	made?;
	settle(layout).await
}

/// A copy of the primary at `host`, made a standby of it.
pub async fn clone(layout: &Layout, host: &str) -> Result<(), Error> {
	clear_partial(layout).await?;
	let mut basebackup = command("pg_basebackup");
	basebackup
		.arg("--pgdata")
		.arg(layout.partial())
		.args(["--host", host, "--port", &render::PORT.to_string(), "--username", REPLICATOR])
		.args(["--wal-method=stream", "--checkpoint=fast", "--no-password"])
		.env("PGPASSFILE", layout.passfile());
	output(basebackup, None).await?;
	let signal = layout.partial().join("standby.signal");
	tokio::fs::write(&signal, "").await.map_err(io(&signal))?;
	settle(layout).await
}

/// This old primary's history wound back to where the primary at `host` forked from it, any WAL
/// it lacks fetched from the archive, and made its standby.
pub async fn rewind(layout: &Layout, host: &str) -> Result<(), Error> {
	let source = render::conninfo(host, SUPERUSER, &layout.passfile(), "pg_rewind");
	let mut rewind = command("pg_rewind");
	rewind
		.arg("--target-pgdata")
		.arg(&layout.data)
		.arg(format!("--source-server={source} dbname=postgres"))
		.arg(format!("--config-file={}", layout.conf().display()))
		.arg("--restore-target-wal");
	output(rewind, None).await?;
	let signal = layout.data.join("standby.signal");
	tokio::fs::write(&signal, "").await.map_err(io(&signal))
}

/// Postgres, in a process group of its own so a signal meant for the keeper never reaches it
/// unasked: the keeper stops it, and stops it fast.
pub fn spawn(layout: &Layout) -> Result<Child, Error> {
	command("postgres")
		.arg("-D")
		.arg(&layout.data)
		.arg("-c")
		.arg(format!("config_file={}", layout.conf().display()))
		.process_group(0)
		.stdin(Stdio::null())
		.spawn()
		.map_err(|source| Error::Spawn { program: "postgres".into(), source })
}

/// Wait until Postgres answers on its socket, or `child` exits.
pub async fn ready(layout: &Layout, child: &mut Child) -> Result<(), Error> {
	for _ in 0..READY_SECONDS {
		if child
			.try_wait()
			.map_err(|source| Error::Spawn { program: "postgres".into(), source })?
			.is_some()
		{
			return Err(Error::Exited);
		}
		if query(layout, "SELECT 1").await.is_ok() {
			return Ok(());
		}
		tokio::time::sleep(Duration::from_secs(1)).await;
	}
	Err(Error::Slow)
}

/// `sql` run as the superuser over the socket, its rows unaligned: columns split by `|`.
pub async fn query(layout: &Layout, sql: &str) -> Result<String, Error> {
	query_in(layout, "postgres", sql).await
}

/// `query`, in the database named.
pub async fn query_in(layout: &Layout, database: &str, sql: &str) -> Result<String, Error> {
	let mut psql = command("psql");
	psql
		.args(["--no-psqlrc", "--no-align", "--tuples-only", "--quiet", "--set=ON_ERROR_STOP=1"])
		.arg("--host")
		.arg(&layout.run)
		.args(["--port", &render::PORT.to_string(), "--username", SUPERUSER, "--dbname", database]);
	output(psql, Some(sql)).await
}

/// On the primary, every start: the role standbys copy as, and both passwords as the environment
/// gives them now, so changing one is a change to `secret.env` and a redeploy. The SQL goes on
/// psql's input, never its arguments.
pub async fn ensure_roles(layout: &Layout, config: &Config) -> Result<(), Error> {
	let sql = format!(
		"DO $$ BEGIN\n\
		 IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '{REPLICATOR}') THEN\n\
		 CREATE ROLE {REPLICATOR} WITH REPLICATION LOGIN;\n\
		 END IF;\n\
		 END $$;\n\
		 ALTER ROLE {REPLICATOR} WITH REPLICATION LOGIN PASSWORD {};\n\
		 ALTER ROLE {SUPERUSER} PASSWORD {};\n",
		render::literal(&config.replication_password),
		render::literal(&config.superuser_password),
	);
	query(layout, &sql).await.map(|_| ())
}

/// A fast shutdown: open sessions are ended and a checkpoint is written. The keeper waits on the
/// process itself.
pub async fn stop(layout: &Layout) -> Result<(), Error> {
	let mut pg_ctl = command("pg_ctl");
	pg_ctl.args(["stop", "--mode=fast", "--no-wait", "--pgdata"]).arg(&layout.data);
	output(pg_ctl, None).await.map(|_| ())
}

#[cfg(test)]
mod tests {
	use super::*;

	#[tokio::test]
	async fn a_stale_lock_is_removed_and_none_is_fine() {
		let dir = tempfile::tempdir().unwrap();
		let layout = Layout { data: dir.path().into(), run: dir.path().into() };
		assert!(!clear_stale_lock(&layout).await.unwrap());
		std::fs::write(dir.path().join("postmaster.pid"), "29\n").unwrap();
		assert!(clear_stale_lock(&layout).await.unwrap());
		assert!(!dir.path().join("postmaster.pid").exists());
	}
}
