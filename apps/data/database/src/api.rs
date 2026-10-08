//! What host and `cron` ask the keeper, on a socket in its directory. See
//! spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use crate::config::Role;
use crate::keeper::{Keeper, Phase, describe};
use axum::Router;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::Response;
use axum::routing::{get, post};
use std::sync::Arc;

/// The socket's name in the app's directory, as `service.toml` declares it, which the test below
/// holds it to.
pub const SOCKET: &str = "database.sock";

pub fn routes(keeper: Arc<Keeper>) -> Router {
	Router::new()
		.route("/health", get(health))
		.route("/jobs/backup", post(backup))
		.route("/jobs/amcheck", post(amcheck))
		.fallback(|| async { response::failure(StatusCode::NOT_FOUND, "no_such_route") })
		.with_state(keeper)
}

fn unavailable(reason: impl ToString) -> Response {
	response::failure_with(StatusCode::SERVICE_UNAVAILABLE, "service_unavailable", reason)
}

/// Healthy while Patroni runs Postgres as a primary or a replica and Postgres answers; a member
/// starting, copying, or with no Patroni answering says which.
async fn health(State(keeper): State<Arc<Keeper>>) -> Response {
	let phase = keeper.phase();
	if !matches!(phase, Phase::Running) {
		return unavailable(describe(&phase));
	}
	match keeper.view().await {
		Ok(view) if view.serving() => {}
		Ok(view) => {
			return unavailable(format!("Patroni says this member is {}, as {}", view.state, view.role));
		}
		Err(error) => return unavailable(error),
	}
	match keeper.status().await {
		Ok(status) => response::success(StatusCode::OK, status),
		Err(error) => unavailable(error),
	}
}

/// The daily backup, which only the leader takes; a standby answers that it had nothing to do,
/// which `cron` records as done.
async fn backup(State(keeper): State<Arc<Keeper>>) -> Response {
	let phase = keeper.phase();
	if !matches!(phase, Phase::Running) {
		return unavailable(describe(&phase));
	}
	let Ok(_running) = keeper.backing_up.try_lock() else {
		return response::failure(StatusCode::CONFLICT, "job_running");
	};
	match keeper.status().await {
		Ok(status) if status.role == Role::Standby => response::success(
			StatusCode::OK,
			serde_json::json!({ "skipped": true, "reason": "a standby takes no backup" }),
		),
		Ok(_) => match keeper.backup(jiff::Timestamp::now()).await {
			Ok(report) => response::success(StatusCode::OK, report),
			Err(error) => unavailable(error),
		},
		Err(error) => unavailable(error),
	}
}

/// The daily index check, on the primary and every standby alike; a broken index, or a database
/// not checked to the end, fails it with their names. See amcheck.rs.
async fn amcheck(State(keeper): State<Arc<Keeper>>) -> Response {
	let phase = keeper.phase();
	if !matches!(phase, Phase::Running) {
		return unavailable(describe(&phase));
	}
	let Ok(_running) = keeper.checking.try_lock() else {
		return response::failure(StatusCode::CONFLICT, "job_running");
	};
	match keeper.amcheck().await {
		Ok(report) => match report.failure() {
			None => response::success(StatusCode::OK, report),
			Some(failure) => unavailable(failure),
		},
		Err(error) => unavailable(error),
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::config::Config;
	use crate::postgres::Layout;
	use axum::body::Body;
	use axum::http::Request;
	use http_body_util::BodyExt;
	use tower::ServiceExt;

	fn keeper() -> Arc<Keeper> {
		let config = Config {
			node: "buf".into(),
			peers: [("buf".to_owned(), "100.64.0.2".to_owned())].into(),
			quorum: vec!["100.64.0.2".into()],
			priority: 1,
			superuser_password: "s".into(),
			replication_password: "r".into(),
			patroni_password: "p".into(),
			data: "/nonexistent".into(),
		};
		Arc::new(Keeper::new(config, Layout::new("/nonexistent".into())))
	}

	async fn ask(keeper: Arc<Keeper>, method: &str, path: &str) -> (StatusCode, serde_json::Value) {
		let request = Request::builder().method(method).uri(path).body(Body::empty()).unwrap();
		let answer = routes(keeper).oneshot(request).await.unwrap();
		let status = answer.status();
		let body = answer.into_body().collect().await.unwrap().to_bytes();
		(status, serde_json::from_slice(&body).unwrap())
	}

	#[tokio::test]
	async fn says_why_it_is_not_healthy_until_patroni_runs() {
		let keeper = keeper();
		let (status, body) = ask(keeper.clone(), "GET", "/health").await;
		assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
		assert_eq!(body["code"], "service_unavailable");
		assert_eq!(body["message"], "writing Patroni's configuration");
		for job in ["/jobs/backup", "/jobs/amcheck"] {
			let (status, body) = ask(keeper.clone(), "POST", job).await;
			assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
			assert_eq!(body["message"], "writing Patroni's configuration");
		}
	}

	#[tokio::test]
	async fn an_unknown_route_is_the_envelope_too() {
		let (status, body) = ask(keeper(), "GET", "/jobs").await;
		assert_eq!(status, StatusCode::NOT_FOUND);
		assert_eq!(body["code"], "no_such_route");
	}

	#[test]
	fn the_socket_is_the_declared_one() {
		let declared = include_str!("../service.toml");
		assert!(declared.contains(&format!("\nsocket = \"{SOCKET}\"\n")));
		for code in response::codes_named(include_str!("api.rs")) {
			assert!(response::message_of(code).is_some(), "{code} is not in the catalogue");
		}
	}
}
