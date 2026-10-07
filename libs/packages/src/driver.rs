//! The one thing the agents do differently: how a job is started on the machine and how its state
//! is read back. See spec/architecture/packages.md, "The agents".

use async_trait::async_trait;

/// One of the two jobs every agent runs. A path names a job, and a job is one of two words, so
/// nothing a request carries becomes part of a command. See spec/architecture/apt.md, "The door".
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Job {
	Update,
	Upgrade,
}

impl Job {
	pub const ALL: [Job; 2] = [Job::Update, Job::Upgrade];

	/// The job's word: its route, its key in `/status` and its ledger task's kind.
	pub fn name(self) -> &'static str {
		match self {
			Job::Update => "update",
			Job::Upgrade => "upgrade",
		}
	}
}

/// How a finished run went, as the ledger is told it.
#[derive(Debug, Clone, PartialEq)]
pub struct Outcome {
	pub success: bool,
	pub result: String,
	/// None when the run ended without one, an interrupted run among them.
	pub exit_status: Option<i32>,
}

/// One job's state, as a driver reads it.
pub trait JobState: Send + Sync + 'static {
	fn running(&self) -> bool;
	/// Whether this reading shows the run started after `before` was read as over.
	fn finished_since(&self, before: &Self) -> bool;
	/// What `/status` and a job's `202` answer with for `job`.
	fn view(&self, job: Job) -> serde_json::Value;
	fn outcome(&self) -> Outcome;
}

/// What the routes and the following of a run need from the machine, behind a trait so both are
/// shared by the agents and testable without a machine.
#[async_trait]
pub trait Driver: Send + Sync + 'static {
	type State: JobState;
	/// The service its runs are recorded under in the ledger.
	const SERVICE: &'static str;
	/// What `state` reads, as a message names it when it cannot be read.
	const READS: &'static str;

	/// Success once the agent can reach what it drives.
	async fn health(&self) -> anyhow::Result<()>;
	async fn state(&self, job: Job) -> anyhow::Result<Self::State>;
	/// Starts `job`, whose state read `before` just before.
	async fn start(&self, job: Job, before: &Self::State) -> anyhow::Result<()>;
	/// What a job runs on the machine, as its `started` event names it.
	fn target(&self, job: Job) -> &'static str;
}
