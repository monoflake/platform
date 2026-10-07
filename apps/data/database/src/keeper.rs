//! The keeper's own state: what it is doing to bring Postgres up, and what it answers with while it
//! does. See spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use crate::backup;
use crate::config::{Config, Role};
use crate::health::{self, Status};
use crate::plan::{self, Plan};
use crate::postgres::{self, Layout};
use crate::watch::{self, Last};
use jiff::{SignedDuration, Timestamp};
use serde::Serialize;
use std::sync::{Mutex, RwLock};
use std::time::Duration;
use tokio::process::Child;

/// How long a standby waits before it asks the primary for a copy again.
const RETRY: Duration = Duration::from_secs(10);

#[derive(Debug, Clone, PartialEq)]
pub enum Phase {
	/// Bringing Postgres up, and how.
	Starting(String),
	/// A step failed and is tried again.
	Waiting(String),
	/// Postgres is not started, and why; nothing but an operator changes that.
	Refused(String),
	Running(Plan),
}

/// What stops a start: a refusal leaves the keeper answering why, anything else ends it.
#[derive(Debug, thiserror::Error)]
pub enum Stopped {
	#[error("{0}")]
	Refused(String),
	#[error(transparent)]
	Failed(#[from] postgres::Error),
	#[error(transparent)]
	Unreadable(#[from] plan::Unreadable),
}

pub struct Keeper {
	pub config: Config,
	pub layout: Layout,
	phase: RwLock<Phase>,
	/// Held while a backup runs, so a second is refused rather than run beside it.
	pub backing_up: tokio::sync::Mutex<()>,
	/// The newest base backup in the store: read once at start, then set by each backup job.
	last: RwLock<Last>,
	/// The backup state last logged, so a change is logged once.
	logged: Mutex<Option<watch::State>>,
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
		let phase = RwLock::new(Phase::Starting("reading the data directory".into()));
		Self {
			config,
			layout,
			phase,
			backing_up: tokio::sync::Mutex::new(()),
			last: RwLock::new(Last::Unknown),
			logged: Mutex::new(None),
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

	pub fn refuse(&self, reason: String) {
		self.set(Phase::Refused(reason));
	}

	/// From whatever the data directory holds to a Postgres accepting connections as this node's
	/// configuration says, or as near as a start may take it.
	pub async fn bring_up(&self) -> Result<Child, Stopped> {
		let (config, layout) = (&self.config, &self.layout);
		let found = plan::found(&layout.data)?;
		let plan = plan::plan(config.role(), found);
		let primary = config.primary_address();
		if found != plan::Found::Empty && postgres::clear_stale_lock(layout).await? {
			eprintln!("database: removed postmaster.pid, left by a Postgres that did not stop cleanly");
		}
		let follow = matches!(plan, Plan::Clone | Plan::Rewind | Plan::Run(Role::Standby));
		postgres::prepare(layout, config, follow.then_some(primary)).await?;
		match plan {
			Plan::Initialize => {
				self.set(Phase::Starting("making the cluster".into()));
				postgres::initialize(layout, config).await?;
			}
			Plan::Clone => loop {
				self.set(Phase::Starting(format!("copying the primary, {}", config.primary)));
				match postgres::clone(layout, primary).await {
					Ok(()) => break,
					Err(error) => {
						self.set(Phase::Waiting(format!("copying the primary failed: {error}")));
						tokio::time::sleep(RETRY).await;
					}
				}
			},
			Plan::Rewind => {
				self.set(Phase::Starting(format!("rewinding onto the primary, {}", config.primary)));
				if let Err(error) = postgres::rewind(layout, primary).await {
					return Err(Stopped::Refused(format!(
						"{} holds a primary and is configured as a standby, and rewinding it onto {} \
						 failed, so Postgres is not started: {error}",
						config.node, config.primary
					)));
				}
			}
			Plan::Run(_) | Plan::AwaitPromotion => {}
		}
		self.set(Phase::Starting("starting Postgres".into()));
		let mut child = postgres::spawn(layout)?;
		postgres::ready(layout, &mut child).await?;
		if matches!(plan, Plan::Initialize | Plan::Run(Role::Primary)) {
			postgres::ensure_roles(layout, config).await?;
		}
		self.set(Phase::Running(plan));
		Ok(child)
	}

	/// What Postgres says it is, against what this node is configured as.
	pub async fn status(&self) -> Result<Status, postgres::Error> {
		let row = postgres::query(&self.layout, health::SELF).await?;
		let unexpected = |error: health::Unexpected| postgres::Error::Failed {
			program: "psql".into(),
			detail: error.to_string(),
		};
		let mut status = health::parse(&row, self.config.role()).map_err(unexpected)?;
		if status.role == Role::Primary {
			let rows = postgres::query(&self.layout, health::STANDBYS).await?;
			status.standbys = Some(health::standbys(&rows).map_err(unexpected)?);
			status.backup = Some(self.watch(Timestamp::now()));
		}
		Ok(status)
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
		Phase::Waiting(why) => format!("{why}; trying again in {} seconds", RETRY.as_secs()),
		Phase::Refused(why) => why.clone(),
		Phase::Running(plan) => format!("running, as {plan:?}"),
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn keeper(data: &std::path::Path) -> Keeper {
		let config = Config {
			node: "tyo".into(),
			primary: "tyo".into(),
			peers: [("tyo".to_owned(), "100.64.0.1".to_owned())].into(),
			superuser_password: "s".into(),
			replication_password: "r".into(),
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
