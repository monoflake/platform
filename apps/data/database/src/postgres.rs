//! Postgres's own programs, run by the keeper beside Patroni, which starts, copies, rewinds and
//! promotes it: asking it things over its socket, keeping its roles, stopping it, and fetching a
//! base backup for a new member.

use crate::config::Config;
use crate::render::{self, REPLICATOR, SUPERUSER};
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::Stdio;
use tokio::io::AsyncWriteExt;
use tokio::process::Command;

/// Where the socket and the configuration written each start go: the container's scratch.
pub const RUN: &str = "/tmp";
/// How long an immediate stop is waited on, which ends in a moment unless something is wrong.
pub const STOP_NOW: std::time::Duration = std::time::Duration::from_secs(5);

#[derive(Debug, thiserror::Error)]
pub enum Error {
	#[error("{program} could not be started: {source}")]
	Spawn { program: String, source: std::io::Error },
	#[error("{program} failed: {detail}")]
	Failed { program: String, detail: String },
	#[error("{path}: {source}")]
	Io { path: String, source: std::io::Error },
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

	/// Where Patroni's configuration is written each start.
	pub fn patroni(&self) -> PathBuf {
		self.run.join("patroni.yml")
	}
}

/// A program with the passwords the keeper was given taken out of its environment: Patroni reads
/// them from its configuration, and Postgres, its archive command and WAL-G read none of them.
pub fn command(program: &str) -> Command {
	let mut command = Command::new(program);
	command
		.env_remove("POSTGRES_PASSWORD")
		.env_remove("REPLICATION_PASSWORD")
		.env_remove("PATRONI_PASSWORD");
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
pub async fn private(path: &Path, content: &str) -> Result<(), Error> {
	tokio::fs::write(path, content).await.map_err(io(path))?;
	tokio::fs::set_permissions(path, std::fs::Permissions::from_mode(0o600)).await.map_err(io(path))
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
	// Its statements carry passwords, which `log_statement = ddl` would write to the log.
	let sql = format!(
		"SET log_statement = 'none';\n\
		 DO $$ BEGIN\n\
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

/// An immediate stop, no checkpoint and no goodbye, for a Postgres whose Patroni is gone or hung:
/// it must stop taking writes now, and crash recovery on the next start puts it right. Nothing to
/// stop is not an error.
pub async fn stop_now(layout: &Layout) -> Result<(), Error> {
	if !layout.data.join("postmaster.pid").exists() {
		return Ok(());
	}
	let mut pg_ctl = command("pg_ctl");
	pg_ctl
		.args(["stop", "--mode=immediate", "--wait"])
		.arg(format!("--timeout={}", STOP_NOW.as_secs()))
		.arg("--pgdata")
		.arg(&layout.data);
	output(pg_ctl, None).await.map(|_| ())
}

/// Patroni's `wal_g` replica method: the latest base backup into the empty data directory it
/// names, after which Patroni follows the primary, catching up from the archive first.
pub async fn fetch_backup(data: &Path) -> Result<(), Error> {
	let mut fetch = command("wal-g");
	fetch.arg("backup-fetch").arg(data).arg("LATEST");
	output(fetch, None).await.map(|_| ())
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
