//! The keeper's own state: Patroni's configuration written and Patroni started, what it answers
//! host and `cron` with, and what it tends on the leader. See spec/architecture/databases.md, "The
//! container is Postgres and a keeper of it".

use crate::amcheck;
use crate::backup;
use crate::config::{Config, Role};
use crate::health::{self, Status};
use crate::patroni::{Rest, View};
use crate::postgres::{self, Layout};
use crate::render;
use crate::watch::{self, Last};
use jiff::{SignedDuration, Timestamp};
use serde::Serialize;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Mutex, RwLock};
use tokio::process::Child;

#[derive(Debug, Clone, PartialEq)]
pub enum Phase {
	/// Writing Patroni's configuration, and why it is not running yet.
	Starting(String),
	/// Patroni runs, and Postgres is its to start, follow, promote and demote.
	Running,
}

pub struct Keeper {
	pub config: Config,
	pub layout: Layout,
	pub rest: Rest,
	phase: RwLock<Phase>,
	/// Held while a backup runs, so a second is refused rather than run beside it.
	pub backing_up: tokio::sync::Mutex<()>,
	/// Held while the indexes are checked, for the same reason.
	pub checking: tokio::sync::Mutex<()>,
	/// The newest base backup in the store: read once a node leads, then set by each backup job.
	last: RwLock<Last>,
	/// The backup state last logged, so a change is logged once.
	logged: Mutex<Option<watch::State>>,
	/// Whether this node's tenure as leader has had its roles kept and its last backup read.
	tended: AtomicBool,
	/// `watch::STALLED_AFTER`, shorter only in a test.
	pub stalled_after: SignedDuration,
}

/// Why a backup job did not finish.
#[derive(Debug, thiserror::Error)]
pub enum Unbacked {
	#[error(
		"archiving has stopped: {segment} has waited {seconds} seconds to be archived, so no base \
		 backup was taken"
	)]
	Stalled { segment: String, seconds: i64 },
	#[error("archive_status could not be read, so no base backup was taken: {0}")]
	Unreadable(std::io::Error),
	#[error(transparent)]
	Failed(#[from] postgres::Error),
}

/// What one backup did.
#[derive(Debug, Serialize)]
pub struct Report {
	pub backup: Option<String>,
	pub marked: Vec<String>,
	pub unmarked: Vec<String>,
	/// Every backup before it that is not permanent was deleted, with the WAL none of them needs.
	pub deleted_before: Option<String>,
	pub backups: usize,
	pub permanent: usize,
}

impl Keeper {
	pub fn new(config: Config, layout: Layout) -> Self {
		let phase = RwLock::new(Phase::Starting("writing Patroni's configuration".into()));
		Self {
			config,
			layout,
			rest: Rest::new(render::REST),
			phase,
			backing_up: tokio::sync::Mutex::new(()),
			checking: tokio::sync::Mutex::new(()),
			last: RwLock::new(Last::Unknown),
			logged: Mutex::new(None),
			tended: AtomicBool::new(false),
			stalled_after: watch::STALLED_AFTER,
		}
	}

	pub fn phase(&self) -> Phase {
		self.phase.read().map_or_else(|poisoned| poisoned.into_inner().clone(), |phase| phase.clone())
	}

	fn set(&self, phase: Phase) {
		eprintln!("database: {}", describe(&phase));
		match self.phase.write() {
			Ok(mut held) => *held = phase,
			Err(poisoned) => *poisoned.into_inner() = phase,
		}
	}

	/// Patroni's configuration written for this start, the directory it writes Postgres's into
	/// made, and any lock a Postgres of an earlier container left cleared: none runs in this one
	/// yet, and its number may be a live process's here.
	pub async fn prepare(&self) -> Result<(), postgres::Error> {
		let run = self.layout.run.join("postgresql");
		tokio::fs::create_dir_all(&run)
			.await
			.map_err(|source| postgres::Error::Io { path: run.display().to_string(), source })?;
		// Patroni includes the base beneath what it writes, and would otherwise move a configuration
		// of initdb's here that does not exist; and its crash recovery in single-user mode, before a
		// rewind, reads postgresql.conf before Patroni has written one. Both start empty: everything
		// Postgres runs with is in patroni.yml.
		for file in ["postgresql.base.conf", "postgresql.conf"] {
			postgres::private(&run.join(file), "").await?;
		}
		let machine = render::Machine::read(&self.layout.data);
		eprintln!(
			"database: tuned for {} MiB, {} cores and a disk of {} GiB",
			machine.memory_mb,
			machine.cpus,
			machine.disk_bytes / (1024 * 1024 * 1024)
		);
		let rendered = render::patroni(&self.config, machine, &self.layout.data, &self.layout.run);
		let text = serde_json::to_string_pretty(&rendered).unwrap_or_default();
		postgres::private(&self.layout.patroni(), &text).await?;
		if postgres::clear_stale_lock(&self.layout).await? {
			eprintln!("database: removed postmaster.pid, left by a Postgres that did not stop cleanly");
		}
		Ok(())
	}

	/// Patroni, in a process group of its own so a signal meant for the keeper never reaches it
	/// unasked: the keeper stops it, and stops it in order.
	pub fn spawn(&self) -> Result<Child, postgres::Error> {
		let child = postgres::command("patroni")
			.arg(self.layout.patroni())
			.process_group(0)
			.stdin(std::process::Stdio::null())
			.spawn()
			.map_err(|source| postgres::Error::Spawn { program: "patroni".into(), source })?;
		self.set(Phase::Running);
		Ok(child)
	}

	/// Patroni's view of this member, or why there is none.
	pub async fn view(&self) -> Result<View, String> {
		self.rest.view().await
	}

	/// What Postgres says it is, Patroni's view beside it, and on the primary its standbys and
	/// whether backing up has stopped.
	pub async fn status(&self) -> Result<Status, postgres::Error> {
		let row = postgres::query(&self.layout, health::SELF).await?;
		let unexpected = |error: health::Unexpected| postgres::Error::Failed {
			program: "psql".into(),
			detail: error.to_string(),
		};
		let mut status = health::parse(&row).map_err(unexpected)?;
		status.patroni = self.view().await.ok();
		if status.role == Role::Primary {
			let rows = postgres::query(&self.layout, health::STANDBYS).await?;
			status.standbys = Some(health::standbys(&rows).map_err(unexpected)?);
			status.backup = Some(self.watch(Timestamp::now()));
		}
		Ok(status)
	}

	/// Asked each minute: on the leader, the roles and passwords kept as the environment gives them
	/// and the last base backup read once a tenure, and whether backing up has stopped; on a
	/// standby, nothing but forgetting the tenure, so the next one tends again.
	pub async fn tend(&self) {
		let Ok(row) = postgres::query(&self.layout, health::SELF).await else { return };
		let Ok(status) = health::parse(&row) else { return };
		if status.role != Role::Primary {
			self.tended.store(false, Ordering::Relaxed);
			return;
		}
		if !self.tended.load(Ordering::Relaxed) {
			match postgres::ensure_roles(&self.layout, &self.config).await {
				Ok(()) => {
					self.seed().await;
					self.tended.store(true, Ordering::Relaxed);
				}
				Err(error) => eprintln!("database: keeping the roles failed: {error}"),
			}
		}
		self.watch(Timestamp::now());
	}

	fn last(&self) -> Last {
		self.last.read().map_or_else(|poisoned| *poisoned.into_inner(), |last| *last)
	}

	fn set_last(&self, last: Last) {
		match self.last.write() {
			Ok(mut held) => *held = last,
			Err(poisoned) => *poisoned.into_inner() = last,
		}
	}

	/// Whether backing up has stopped, logged once each time the answer changes.
	pub fn watch(&self, now: Timestamp) -> watch::Backup {
		let read = watch::read_waiting(&self.layout.data).map_err(|_| ());
		let report = watch::report(read, self.last(), now, self.stalled_after);
		let mut logged = self.logged.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
		if *logged != Some(report.state) {
			if logged.is_some() || report.state != watch::State::Unknown {
				eprintln!("database: backing up is {}: {}", state_name(report.state), explain(&report));
			}
			*logged = Some(report.state);
		}
		report
	}

	/// The newest base backup in the store, read once in the background; a failure leaves it
	/// unknown until the next backup job says.
	pub async fn seed(&self) {
		match self.list().await {
			Ok(backups) => {
				if self.last() == Last::Unknown {
					self.set_last(newest(&backups));
				}
			}
			Err(error) => eprintln!("database: the last base backup is unknown: {error}"),
		}
	}

	/// A base backup of this primary, then the older ones thinned to the tiers: marked and unmarked
	/// first, and deleted only once every step before has succeeded.
	pub async fn backup(&self, now: Timestamp) -> Result<Report, Unbacked> {
		let waiting = watch::read_waiting(&self.layout.data).map_err(Unbacked::Unreadable)?;
		if watch::archiving(waiting.as_ref(), now, self.stalled_after) == watch::Archiving::Stalled
			&& let Some(waiting) = waiting
		{
			let seconds = now.duration_since(waiting.since).as_secs();
			return Err(Unbacked::Stalled { segment: waiting.segment, seconds });
		}
		let mut push = postgres::command("wal-g");
		push.arg("backup-push").arg(&self.layout.data);
		postgres::output(push, None).await?;
		let backups = self.list().await?;
		self.set_last(newest(&backups));
		let latest = backups.iter().max_by_key(|b| b.start_time).map(|b| b.backup_name.clone());
		let changes = backup::changes(&backups, now);
		for (name, flags) in changes
			.mark
			.iter()
			.map(|name| (name, &[][..]))
			.chain(changes.unmark.iter().map(|name| (name, &["-i"][..])))
		{
			let mut mark = postgres::command("wal-g");
			mark.arg("backup-mark").args(flags).arg(name);
			postgres::output(mark, None).await?;
		}
		if let Some(name) = &changes.delete_before {
			let mut delete = postgres::command("wal-g");
			delete.args(["delete", "before", name, "--confirm"]);
			postgres::output(delete, None).await?;
		}
		let left = self.list().await?;
		Ok(Report {
			backup: latest,
			marked: changes.mark,
			unmarked: changes.unmark,
			deleted_before: changes.delete_before,
			backups: left.len(),
			permanent: left.iter().filter(|b| b.is_permanent).count(),
		})
	}

	/// Every btree index of every database checked, amcheck installed first where this node is the
	/// primary. See amcheck.rs.
	pub async fn amcheck(&self) -> Result<amcheck::Report, postgres::Error> {
		let role = self.status().await?.role;
		let names = postgres::query(&self.layout, amcheck::DATABASES).await?;
		let mut databases = Vec::new();
		for name in names.lines().map(str::trim).filter(|name| !name.is_empty()) {
			databases.push(self.amcheck_in(name, role).await);
		}
		Ok(amcheck::Report { role, databases })
	}

	async fn amcheck_in(&self, name: &str, role: Role) -> amcheck::Database {
		let mut database = amcheck::Database::new(name);
		let installed = match role {
			Role::Primary => postgres::query_in(&self.layout, name, amcheck::INSTALL).await.map(|_| true),
			Role::Standby => postgres::query_in(&self.layout, name, amcheck::INSTALLED)
				.await
				.map(|out| out.trim() == "t"),
		};
		match installed {
			Ok(true) => {}
			Ok(false) => {
				database.passed_over =
					Some("amcheck is not installed in it yet; the primary's check installs it".into());
				return database;
			}
			Err(error) => {
				database.unfinished = Some(error.to_string());
				return database;
			}
		}
		match postgres::query_in(&self.layout, name, &amcheck::script()).await {
			Ok(out) => match amcheck::parse(&out) {
				Ok(checked) => database.record(checked),
				Err(error) => database.unfinished = Some(format!("its answer was unreadable: {error}")),
			},
			Err(error) => database.unfinished = Some(error.to_string()),
		}
		database
	}

	async fn list(&self) -> Result<Vec<backup::Listed>, postgres::Error> {
		let mut list = postgres::command("wal-g");
		list.args(["backup-list", "--detail", "--json"]);
		let out = postgres::output(list, None).await?;
		backup::listed(&out).map_err(|error| postgres::Error::Failed {
			program: "wal-g".into(),
			detail: error.to_string(),
		})
	}
}

/// The newest base backup of a listing.
fn newest(backups: &[backup::Listed]) -> Last {
	backups.iter().map(|b| b.start_time).max().map_or(Last::None, Last::At)
}

fn state_name(state: watch::State) -> &'static str {
	match state {
		watch::State::Ok => "ok",
		watch::State::Stopped => "stopped",
		watch::State::Unknown => "unknown",
	}
}

/// What a backup report says, in a line for the log.
fn explain(report: &watch::Backup) -> String {
	let waiting = match (&report.oldest_waiting, report.oldest_waiting_seconds) {
		(Some(segment), Some(seconds)) => format!("{segment} waiting {seconds} seconds to be archived"),
		_ => "nothing waiting to be archived".into(),
	};
	let last = report
		.last_base_backup
		.map_or_else(|| "no base backup known".into(), |at| format!("last base backup {at}"));
	format!("{waiting}, {last}")
}

/// A phase as a sentence, for the log and for `/health`.
pub fn describe(phase: &Phase) -> String {
	match phase {
		Phase::Starting(doing) => doing.clone(),
		Phase::Running => "Patroni runs".into(),
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn keeper(data: &std::path::Path) -> Keeper {
		let config = Config {
			node: "tyo".into(),
			peers: [("tyo".to_owned(), "100.64.0.1".to_owned())].into(),
			quorum: vec!["100.64.0.1".into()],
			priority: 3,
			superuser_password: "s".into(),
			replication_password: "r".into(),
			patroni_password: "p".into(),
			data: data.into(),
		};
		Keeper::new(config, Layout::new(data.into()))
	}

	#[tokio::test]
	async fn the_job_refuses_while_archiving_has_stopped() {
		let dir = tempfile::tempdir().unwrap();
		let status = dir.path().join("pg_wal/archive_status");
		std::fs::create_dir_all(&status).unwrap();
		std::fs::write(status.join("000000010000000000000003.ready"), "").unwrap();
		let mut keeper = keeper(dir.path());
		keeper.stalled_after = SignedDuration::ZERO;
		let later = Timestamp::now() + SignedDuration::from_secs(5);
		let error = keeper.backup(later).await.unwrap_err();
		assert!(
			matches!(&error, Unbacked::Stalled { segment, .. } if segment == "000000010000000000000003")
		);
		assert!(error.to_string().contains("no base backup was taken"));
		assert_eq!(keeper.watch(later).state, watch::State::Stopped);
	}
}
