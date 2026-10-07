//! `apt`'s driver: a job is one of two systemd units, started and read over the bus. See
//! spec/architecture/apt.md, "It starts a unit through systemd's D-Bus API".

use crate::bus::{Bus, Properties, UNIT_UPDATE, UNIT_UPGRADE};
use async_trait::async_trait;
use packages::{Driver, Job, JobState, Outcome};
use std::sync::Arc;

/// The unit a job starts. The two names are constants, so a job is a unit and nothing else is.
/// See spec/architecture/apt.md, "The door".
pub fn unit_of(job: Job) -> &'static str {
	match job {
		Job::Update => UNIT_UPDATE,
		Job::Upgrade => UNIT_UPGRADE,
	}
}

pub struct Units {
	pub bus: Arc<dyn Bus>,
}

#[async_trait]
impl Driver for Units {
	type State = Properties;
	const SERVICE: &'static str = "apt";
	const READS: &'static str = "the unit's properties";

	/// Success once systemd answers at all -- read through `UNIT_UPDATE`, though which unit is
	/// asked about does not matter here.
	async fn health(&self) -> anyhow::Result<()> {
		self.bus.properties(UNIT_UPDATE).await.map(|_| ())
	}

	async fn state(&self, job: Job) -> anyhow::Result<Properties> {
		self.bus.properties(unit_of(job)).await
	}

	async fn start(&self, job: Job, _before: &Properties) -> anyhow::Result<()> {
		self.bus.start(unit_of(job)).await
	}

	fn target(&self, job: Job) -> &'static str {
		unit_of(job)
	}
}

impl JobState for Properties {
	fn running(&self) -> bool {
		Properties::running(self)
	}

	/// A unit's last run is the one it settled from, whatever ran before.
	fn finished_since(&self, _before: &Self) -> bool {
		!Properties::running(self)
	}

	/// Its unit, whether it is running, and its last run, when it has had one.
	fn view(&self, job: Job) -> serde_json::Value {
		let last_run = (self.exec_main_start_timestamp != 0).then(|| {
			serde_json::json!({
				"started_at": micros(self.exec_main_start_timestamp),
				"finished_at": (self.exec_main_exit_timestamp != 0)
					.then(|| micros(self.exec_main_exit_timestamp)),
				"result": self.result,
				"exit_status": self.exec_main_status,
			})
		});
		serde_json::json!({
			"unit": unit_of(job),
			"running": Properties::running(self),
			"last_run": last_run,
		})
	}

	fn outcome(&self) -> Outcome {
		Outcome {
			success: self.result == "success",
			result: self.result.clone(),
			exit_status: Some(self.exec_main_status),
		}
	}
}

/// Microseconds since the epoch, as systemd gives a unit's timestamps, read as RFC 3339.
fn micros(value: u64) -> Option<String> {
	i64::try_from(value)
		.ok()
		.and_then(|us| jiff::Timestamp::from_microsecond(us).ok())
		.map(|at| at.to_string())
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::bus::tests::FakeBus;
	use axum::Router;
	use axum::body::Body;
	use axum::http::{Request, StatusCode};
	use http_body_util::BodyExt;
	use packages::{AppState, routes};
	use std::time::Duration;
	use tower::ServiceExt;

	fn state(bus: FakeBus) -> AppState<Units> {
		AppState { driver: Arc::new(Units { bus: Arc::new(bus) }), ledger: None }
	}

	async fn ask(
		router: Router,
		method: &str,
		path: &str,
		parent: Option<&str>,
	) -> (StatusCode, serde_json::Value) {
		let mut request = Request::builder().method(method).uri(path);
		if let Some(parent) = parent {
			request = request.header("x-task-parent", parent);
		}
		let request = request.body(Body::empty()).unwrap();
		let answer = router.oneshot(request).await.unwrap();
		let status = answer.status();
		let body = answer.into_body().collect().await.unwrap().to_bytes();
		(status, serde_json::from_slice(&body).unwrap())
	}

	#[test]
	fn a_job_names_its_unit() {
		assert_eq!(unit_of(Job::Update), UNIT_UPDATE);
		assert_eq!(unit_of(Job::Upgrade), UNIT_UPGRADE);
	}

	#[tokio::test]
	async fn health_and_status_read_the_bus() {
		let router = routes(state(FakeBus::idle()));
		assert_eq!(ask(router.clone(), "GET", "/health", None).await.0, StatusCode::OK);

		let (status, body) = ask(router, "GET", "/status", None).await;
		assert_eq!(status, StatusCode::OK);
		assert_eq!(body["data"]["update"]["unit"], "apt-nightly-update.service");
		assert_eq!(body["data"]["update"]["running"], false);
		assert_eq!(body["data"]["update"]["last_run"], serde_json::Value::Null);
	}

	#[tokio::test]
	async fn starting_a_job_answers_202_with_its_state() {
		let router = routes(state(FakeBus::starting()));
		let (status, body) = ask(router, "POST", "/jobs/update", Some("cron:abc")).await;
		assert_eq!(status, StatusCode::ACCEPTED);
		assert_eq!(body["data"]["unit"], "apt-nightly-update.service");
		assert_eq!(body["data"]["running"], true);
	}

	#[tokio::test]
	async fn a_running_job_refuses_a_second_start() {
		let router = routes(state(FakeBus::always_active()));
		let (status, body) = ask(router, "POST", "/jobs/upgrade", None).await;
		assert_eq!(status, StatusCode::CONFLICT);
		assert_eq!(body["code"], "job_running");
	}

	#[tokio::test]
	async fn an_unknown_route_is_the_envelope_too() {
		let router = routes(state(FakeBus::idle()));
		let (status, body) = ask(router, "GET", "/jobs", None).await;
		assert_eq!(status, StatusCode::NOT_FOUND);
		assert_eq!(body["code"], "no_such_route");
	}

	#[tokio::test]
	async fn a_run_is_followed_from_activating_to_done() {
		let bus = Arc::new(FakeBus::activating_then_done());
		let units = Arc::new(Units { bus: bus.clone() });
		let before = Properties::default();
		let properties =
			packages::run::start_and_follow(units, None, Job::Update, before, None).await.unwrap();
		assert!(properties.running());
		// The background follow-up polls fast in the fake and settles almost at once.
		tokio::time::sleep(Duration::from_millis(50)).await;
		assert_eq!(bus.started(), vec![UNIT_UPDATE.to_owned()]);
		let settled = bus.properties(UNIT_UPDATE).await.unwrap();
		assert!(!settled.running());
		assert_eq!(settled.result, "success");
	}

	#[test]
	fn a_settled_run_reads_as_its_outcome() {
		let failed =
			Properties { result: "exit-code".into(), exec_main_status: 100, ..Default::default() };
		assert_eq!(
			failed.outcome(),
			Outcome { success: false, result: "exit-code".into(), exit_status: Some(100) }
		);
	}
}
