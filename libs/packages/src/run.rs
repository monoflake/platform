//! Starting a job and following it: reading its state until the run is over, then recording the
//! result. Every run is a ledger task of the agent's own, its parent the task named in
//! `X-Task-Parent`. See spec/architecture/apt.md, "The door".

use crate::driver::{Driver, Job, JobState, Outcome};
use jiff::Timestamp;
use std::sync::Arc;
use std::time::Duration;
use uuid::Uuid;

/// How often a started job's state is read while its run is not over.
const POLL: Duration = Duration::from_secs(2);
/// How many times reading the state may fail in a row before a run is given up on and recorded
/// failed, rather than followed forever.
const RETRIES: u32 = 5;
/// How long a run is followed before it is given up on and recorded failed, not seen to end: the
/// longest timeout `cron` gives either job, the upgrade's two hours, and an hour more.
const CEILING: Duration = Duration::from_secs(3 * 60 * 60);

/// The parent task named in `X-Task-Parent: <service>:<id>`, when the header is present and reads
/// as one. See spec/architecture/cron.md, "A run is a request, and a task in the ledger".
pub fn parent_of(header: Option<&str>) -> Option<ledger::Parent> {
	let (service, id) = header?.split_once(':')?;
	Some(ledger::Parent { service: service.to_owned(), id: id.to_owned() })
}

/// Starts `job`, tells the ledger it is running, and hands the follow-up off to a background
/// task. Returns the state read right after starting, for the route's `202` answer.
pub async fn start_and_follow<D: Driver>(
	driver: Arc<D>,
	ledger: Option<ledger::Ledger>,
	job: Job,
	before: D::State,
	parent: Option<ledger::Parent>,
) -> anyhow::Result<D::State> {
	let id = Uuid::new_v4().to_string();
	let asked_at = Timestamp::now();
	let told = Told { service: D::SERVICE, id: id.clone(), job, asked_at, parent };
	told.tell(&ledger, ledger::State::Queued, None, None, None);

	driver.start(job, &before).await?;

	let started_at = Timestamp::now();
	if let Some(ledger) = &ledger {
		ledger.task(D::SERVICE, id).event(
			"started",
			ledger::Level::Info,
			format!("started {}", driver.target(job)),
			serde_json::Value::Null,
		);
	}
	told.tell(&ledger, ledger::State::Running, Some(started_at), None, None);

	let state = driver.state(job).await?;
	tokio::spawn(follow(driver, ledger, told, before, started_at));
	Ok(state)
}

async fn follow<D: Driver>(
	driver: Arc<D>,
	ledger: Option<ledger::Ledger>,
	told: Told,
	before: D::State,
	started_at: Timestamp,
) {
	let deadline = tokio::time::Instant::now() + CEILING;
	let mut failures = 0;
	loop {
		match driver.state(told.job).await {
			Ok(_) if tokio::time::Instant::now() >= deadline => {
				finish::<D>(&ledger, &told, started_at, Ended::Unseen);
				return;
			}
			Ok(state) if !state.finished_since(&before) => {
				failures = 0;
				tokio::time::sleep(POLL).await;
			}
			Ok(state) => {
				finish::<D>(&ledger, &told, started_at, Ended::Read(state.outcome()));
				return;
			}
			Err(error) => {
				failures += 1;
				eprintln!("{}: reading {}: {error}", D::SERVICE, D::READS);
				if failures >= RETRIES {
					finish::<D>(&ledger, &told, started_at, Ended::Unreadable);
					return;
				}
				tokio::time::sleep(POLL).await;
			}
		}
	}
}

/// How the following of a run ended.
enum Ended {
	Read(Outcome),
	/// Reading the state failed `RETRIES` times in a row.
	Unreadable,
	/// The run was still not over at `CEILING`.
	Unseen,
}

fn finish<D: Driver>(
	ledger: &Option<ledger::Ledger>,
	told: &Told,
	started_at: Timestamp,
	ended: Ended,
) {
	let finished_at = Timestamp::now();
	let job = told.job.name();
	let success = matches!(&ended, Ended::Read(outcome) if outcome.success);
	let seconds = finished_at.duration_since(started_at).as_secs_f64();

	if let Some(ledger) = ledger {
		let (message, data) = match &ended {
			Ended::Read(outcome) => (
				format!("{job} {}", if success { "succeeded" } else { "failed" }),
				serde_json::json!({
					"result": outcome.result,
					"exit_status": outcome.exit_status,
					"seconds": seconds,
				}),
			),
			Ended::Unreadable => (format!("{job}: could not read {}", D::READS), serde_json::Value::Null),
			Ended::Unseen => {
				(format!("{job}: not seen to end"), serde_json::json!({ "seconds": seconds }))
			}
		};
		let level = if success { ledger::Level::Info } else { ledger::Level::Error };
		ledger.task(D::SERVICE, told.id.clone()).event("finished", level, message, data);
	}

	let detail = match &ended {
		Ended::Read(_) if success => None,
		Ended::Read(outcome) => Some(match outcome.exit_status {
			Some(status) => format!("{} (exit {status})", outcome.result),
			None => outcome.result.clone(),
		}),
		Ended::Unreadable => Some(format!("{} could not be read", D::READS)),
		Ended::Unseen => Some(format!("not seen to end within {} hours", CEILING.as_secs() / 3600)),
	};
	let state = if success { ledger::State::Done } else { ledger::State::Failed };
	told.tell(ledger, state, Some(started_at), Some(finished_at), detail);
}

/// What every record of one run carries, whatever its state.
struct Told {
	service: &'static str,
	id: String,
	job: Job,
	asked_at: Timestamp,
	parent: Option<ledger::Parent>,
}

impl Told {
	fn tell(
		&self,
		ledger: &Option<ledger::Ledger>,
		state: ledger::State,
		started_at: Option<Timestamp>,
		finished_at: Option<Timestamp>,
		detail: Option<String>,
	) {
		let Some(ledger) = ledger else { return };
		let record = ledger::Record {
			service: self.service.into(),
			id: self.id.clone(),
			kind: self.job.name().to_owned(),
			state,
			caller: ledger::Caller::Ours,
			asked_at: self.asked_at,
			started_at,
			finished_at,
			summary: serde_json::Value::Null,
			detail,
		};
		ledger.send(ledger::Task { record, parent: self.parent.clone() });
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::api::tests::FakeDriver;

	#[test]
	fn a_parent_header_reads_as_service_and_id() {
		assert_eq!(
			parent_of(Some("cron:abc-123")),
			Some(ledger::Parent { service: "cron".into(), id: "abc-123".into() })
		);
		assert_eq!(parent_of(Some("no-colon")), None);
		assert_eq!(parent_of(None), None);
	}

	#[tokio::test]
	async fn a_run_is_followed_until_it_is_over_and_no_further() {
		let driver = Arc::new(FakeDriver::new(vec![false, true, false]));
		let before = driver.state(Job::Update).await.unwrap();
		let state = start_and_follow(driver.clone(), None, Job::Update, before, None).await.unwrap();
		assert!(state.running());
		// The follow-up finds the run over on its first read, so it never waits out `POLL`.
		tokio::time::sleep(Duration::from_millis(50)).await;
		assert_eq!(driver.started(), vec![Job::Update]);
		assert_eq!(driver.reads(), 3);
	}

	#[tokio::test(start_paused = true)]
	async fn a_run_never_seen_to_end_is_given_up_at_the_ceiling() {
		let driver = Arc::new(FakeDriver::new(vec![false, true]));
		let before = driver.state(Job::Upgrade).await.unwrap();
		start_and_follow(driver.clone(), None, Job::Upgrade, before, None).await.unwrap();
		tokio::time::sleep(CEILING + POLL * 2).await;
		let given_up = driver.reads();
		tokio::time::sleep(POLL * 10).await;
		assert_eq!(driver.reads(), given_up);
		assert!(given_up as u128 > CEILING.as_millis() / POLL.as_millis());
	}
}
