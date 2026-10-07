//! What `cron` asks, over a Unix socket in the agent's own directory: no port, no network. See
//! spec/architecture/packages.md, "The interface is the layer", and spec/architecture/apt.md, "The
//! door".

use crate::driver::{Driver, Job, JobState};
use crate::run;
use axum::Router;
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::Response;
use axum::routing::{get, post};
use std::path::Path;
use std::sync::Arc;

pub struct AppState<D> {
	pub driver: Arc<D>,
	/// None in a test that does not care what is told.
	pub ledger: Option<ledger::Ledger>,
}

impl<D> Clone for AppState<D> {
	fn clone(&self) -> Self {
		Self { driver: self.driver.clone(), ledger: self.ledger.clone() }
	}
}

pub fn routes<D: Driver>(state: AppState<D>) -> Router {
	Router::new()
		.route("/health", get(health::<D>))
		.route("/status", get(status::<D>))
		.route("/jobs/update", post(job_update::<D>))
		.route("/jobs/upgrade", post(job_upgrade::<D>))
		.fallback(|| async { response::failure(StatusCode::NOT_FOUND, "no_such_route") })
		.with_state(state)
}

/// Answers on `socket` in `directory` until the process is told to stop.
pub async fn serve<D: Driver>(
	state: AppState<D>,
	directory: &Path,
	socket: &str,
) -> anyhow::Result<()> {
	// A socket left by a run that did not stop cleanly would refuse the bind.
	let socket = directory.join(socket);
	let _ = std::fs::remove_file(&socket);
	let listener = tokio::net::UnixListener::bind(&socket)?;
	// Made by root, it would refuse `cron`, which runs as nobody; the mount is the door. See
	// spec/architecture/apt.md, "The door".
	std::fs::set_permissions(&socket, std::os::unix::fs::PermissionsExt::from_mode(0o666))?;
	eprintln!("{}: answering on {}", D::SERVICE, socket.display());
	axum::serve(listener, routes(state)).with_graceful_shutdown(stopped()).await?;

	let _ = std::fs::remove_file(&socket);
	Ok(())
}

/// `docker stop` sends SIGTERM, and a process that is PID 1 in its container ignores it unless it
/// asks.
async fn stopped() {
	let terminated = async {
		if let Ok(mut signal) =
			tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
		{
			signal.recv().await;
		}
	};
	tokio::select! {
		_ = tokio::signal::ctrl_c() => {}
		() = terminated => {}
	}
}

async fn health<D: Driver>(State(state): State<AppState<D>>) -> Response {
	match state.driver.health().await {
		Ok(()) => response::success(StatusCode::OK, ()),
		Err(_) => response::failure(StatusCode::SERVICE_UNAVAILABLE, "service_unavailable"),
	}
}

async fn status<D: Driver>(State(state): State<AppState<D>>) -> Response {
	let update = state.driver.state(Job::Update).await;
	let upgrade = state.driver.state(Job::Upgrade).await;
	match (update, upgrade) {
		(Ok(update), Ok(upgrade)) => response::success(
			StatusCode::OK,
			serde_json::json!({
				Job::Update.name(): update.view(Job::Update),
				Job::Upgrade.name(): upgrade.view(Job::Upgrade),
			}),
		),
		_ => response::failure(StatusCode::SERVICE_UNAVAILABLE, "service_unavailable"),
	}
}

async fn job_update<D: Driver>(State(state): State<AppState<D>>, headers: HeaderMap) -> Response {
	start_job(&state, Job::Update, parent_header(&headers)).await
}

async fn job_upgrade<D: Driver>(State(state): State<AppState<D>>, headers: HeaderMap) -> Response {
	start_job(&state, Job::Upgrade, parent_header(&headers)).await
}

fn parent_header(headers: &HeaderMap) -> Option<&str> {
	headers.get("x-task-parent")?.to_str().ok()
}

/// Starts a job and answers `202` with its state; `409` while it is already running. See
/// spec/architecture/packages.md, "The interface is the layer".
async fn start_job<D: Driver>(state: &AppState<D>, job: Job, parent: Option<&str>) -> Response {
	let before = match state.driver.state(job).await {
		Ok(before) => before,
		Err(_) => return response::failure(StatusCode::SERVICE_UNAVAILABLE, "service_unavailable"),
	};
	if before.running() {
		return response::failure(StatusCode::CONFLICT, "job_running");
	}

	let parent = run::parent_of(parent);
	match run::start_and_follow(state.driver.clone(), state.ledger.clone(), job, before, parent).await
	{
		Ok(now) => response::success(StatusCode::ACCEPTED, now.view(job)),
		Err(_) => response::failure(StatusCode::SERVICE_UNAVAILABLE, "service_unavailable"),
	}
}

/// A driver that never touches a machine, for the routes and the following of a run. Shared with
/// `run.rs`'s own tests through `crate::api::tests`.
#[cfg(test)]
pub(crate) mod tests {
	use super::*;
	use crate::driver::Outcome;
	use async_trait::async_trait;
	use axum::body::Body;
	use axum::http::Request;
	use http_body_util::BodyExt;
	use std::sync::Mutex;
	use tower::ServiceExt;

	pub struct FakeState {
		running: bool,
	}

	impl JobState for FakeState {
		fn running(&self) -> bool {
			self.running
		}

		fn finished_since(&self, _before: &Self) -> bool {
			!self.running
		}

		fn view(&self, job: Job) -> serde_json::Value {
			serde_json::json!({ "job": job.name(), "running": self.running })
		}

		fn outcome(&self) -> Outcome {
			Outcome { success: true, result: "success".into(), exit_status: Some(0) }
		}
	}

	/// `state` steps through a fixed script of whether the job is running, one entry per call,
	/// repeating the last once it runs out; `start` only records what it was asked to start, and
	/// fails when the fake is closed.
	pub struct FakeDriver {
		script: Mutex<Vec<bool>>,
		reads: Mutex<usize>,
		started: Mutex<Vec<Job>>,
		closed: bool,
	}

	impl FakeDriver {
		pub fn new(script: Vec<bool>) -> Self {
			assert!(!script.is_empty(), "a fake driver needs at least one answer");
			Self {
				script: Mutex::new(script),
				reads: Mutex::new(0),
				started: Mutex::default(),
				closed: false,
			}
		}

		pub fn closed() -> Self {
			Self { closed: true, ..Self::new(vec![false]) }
		}

		pub fn started(&self) -> Vec<Job> {
			self.started.lock().unwrap().clone()
		}

		pub fn reads(&self) -> usize {
			*self.reads.lock().unwrap()
		}
	}

	#[async_trait]
	impl Driver for FakeDriver {
		type State = FakeState;
		const SERVICE: &'static str = "fake";
		const READS: &'static str = "the fake's state";

		async fn health(&self) -> anyhow::Result<()> {
			if self.closed { Err(anyhow::anyhow!("closed")) } else { Ok(()) }
		}

		async fn state(&self, _job: Job) -> anyhow::Result<FakeState> {
			*self.reads.lock().unwrap() += 1;
			let mut script = self.script.lock().unwrap();
			let running = if script.len() > 1 { script.remove(0) } else { script[0] };
			Ok(FakeState { running })
		}

		async fn start(&self, job: Job, _before: &FakeState) -> anyhow::Result<()> {
			if self.closed {
				anyhow::bail!("closed");
			}
			self.started.lock().unwrap().push(job);
			Ok(())
		}

		fn target(&self, job: Job) -> &'static str {
			job.name()
		}
	}

	fn state(driver: FakeDriver) -> AppState<FakeDriver> {
		AppState { driver: Arc::new(driver), ledger: None }
	}

	async fn ask(router: Router, method: &str, path: &str) -> (StatusCode, serde_json::Value) {
		let request = Request::builder().method(method).uri(path).body(Body::empty()).unwrap();
		let answer = router.oneshot(request).await.unwrap();
		let status = answer.status();
		let body = answer.into_body().collect().await.unwrap().to_bytes();
		(status, serde_json::from_slice(&body).unwrap())
	}

	#[tokio::test]
	async fn health_and_status_read_the_driver() {
		let router = routes(state(FakeDriver::new(vec![false])));
		assert_eq!(ask(router.clone(), "GET", "/health").await.0, StatusCode::OK);
		let (status, body) = ask(router, "GET", "/status").await;
		assert_eq!(status, StatusCode::OK);
		assert_eq!(body["data"]["update"]["job"], "update");
		assert_eq!(body["data"]["upgrade"]["running"], false);

		let router = routes(state(FakeDriver::closed()));
		let (status, body) = ask(router, "GET", "/health").await;
		assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
		assert_eq!(body["code"], "service_unavailable");
	}

	#[tokio::test]
	async fn starting_a_job_answers_202_with_its_state() {
		let router = routes(state(FakeDriver::new(vec![false, true])));
		let (status, body) = ask(router, "POST", "/jobs/upgrade").await;
		assert_eq!(status, StatusCode::ACCEPTED);
		assert_eq!(body["data"]["job"], "upgrade");
		assert_eq!(body["data"]["running"], true);
	}

	#[tokio::test]
	async fn a_running_job_refuses_a_second_start() {
		let driver = Arc::new(FakeDriver::new(vec![true]));
		let router = routes(AppState { driver: driver.clone(), ledger: None });
		let (status, body) = ask(router, "POST", "/jobs/update").await;
		assert_eq!(status, StatusCode::CONFLICT);
		assert_eq!(body["code"], "job_running");
		assert!(driver.started().is_empty());
	}

	#[tokio::test]
	async fn a_start_that_fails_is_unavailable() {
		let router = routes(state(FakeDriver::closed()));
		let (status, body) = ask(router, "POST", "/jobs/update").await;
		assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
		assert_eq!(body["code"], "service_unavailable");
	}

	#[tokio::test]
	async fn an_unknown_route_is_the_envelope_too() {
		let router = routes(state(FakeDriver::new(vec![false])));
		let (status, body) = ask(router, "GET", "/jobs").await;
		assert_eq!(status, StatusCode::NOT_FOUND);
		assert_eq!(body["code"], "no_such_route");
	}

	#[test]
	fn every_code_it_answers_with_is_in_the_catalogue() {
		for code in response::codes_named(include_str!("api.rs")) {
			assert!(
				response::message_of(code).is_some(),
				"`{code}` is not in the response crate's codes.json"
			);
		}
	}
}
