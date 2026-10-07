//! The keeper's own state: what it is doing to bring Postgres up, and what it answers with while it
//! does. See spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use crate::backup;
use crate::config::{Config, Role};
use crate::health::{self, Status};
use crate::plan::{self, Plan};
use crate::postgres::{self, Layout};
use serde::Serialize;
use std::sync::RwLock;
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
		Self { config, layout, phase, backing_up: tokio::sync::Mutex::new(()) }
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
		}
		Ok(status)
	}

	/// A base backup of this primary, then the older ones thinned to the tiers: marked and unmarked
	/// first, and deleted only once every step before has succeeded.
	pub async fn backup(&self, now: jiff::Timestamp) -> Result<Report, postgres::Error> {
		let mut push = postgres::command("wal-g");
		push.arg("backup-push").arg(&self.layout.data);
		postgres::output(push, None).await?;
		let backups = self.list().await?;
		let newest = backups.iter().max_by_key(|b| b.start_time).map(|b| b.backup_name.clone());
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
			backup: newest,
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

/// A phase as a sentence, for the log and for `/health`.
pub fn describe(phase: &Phase) -> String {
	match phase {
		Phase::Starting(doing) => doing.clone(),
		Phase::Waiting(why) => format!("{why}; trying again in {} seconds", RETRY.as_secs()),
		Phase::Refused(why) => why.clone(),
		Phase::Running(plan) => format!("running, as {plan:?}"),
	}
}
