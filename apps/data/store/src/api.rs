//! What host and `cron` ask the store, on a socket in its directory. See spec/architecture/cron.md,
//! "A job is declared by the service that does it".

use crate::store::Store;
use axum::Router;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::Response;
use axum::routing::{get, post};
use std::sync::Arc;

/// The socket's name in the app's directory, as `service.toml` declares it, which the test below
/// holds it to.
pub const SOCKET: &str = "store.sock";

pub fn routes(store: Arc<Store>) -> Router {
	Router::new()
		.route("/health", get(health))
		.route("/jobs/mirror", post(mirror))
		.fallback(|| async { response::failure(StatusCode::NOT_FOUND, "no_such_route") })
		.with_state(store)
}

/// Healthy while it answers; whether the mirror can run yet is said, not failed on, so a key not
/// yet entered never makes the store undeployable.
async fn health(State(store): State<Arc<Store>>) -> Response {
	let source = store.config.source.as_ref().err().map(ToString::to_string);
	response::success(
		StatusCode::OK,
		serde_json::json!({ "mirror": if source.is_none() { "configured" } else { "unconfigured" },
			"reason": source }),
	)
}

/// The daily copy of the database's backups; see store.rs.
async fn mirror(State(store): State<Arc<Store>>) -> Response {
	let Ok(_running) = store.mirroring.try_lock() else {
		return response::failure(StatusCode::CONFLICT, "job_running");
	};
	match store.mirror().await {
		Ok(report) => response::success(StatusCode::OK, report),
		Err(error) => {
			response::failure_with(StatusCode::SERVICE_UNAVAILABLE, "service_unavailable", error)
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::config::Config;
	use axum::body::Body;
	use axum::http::Request;
	use http_body_util::BodyExt;
	use tower::ServiceExt;

	fn store() -> Arc<Store> {
		let env = |key: &str| match key {
			"S3_ENDPOINT" => Some("the-sidecar".to_owned()),
			"S3_REGION" | "S3_ACCESS_KEY_ID" | "S3_SECRET_ACCESS_KEY" => Some("x".to_owned()),
			"S3_BUCKETS" => Some("backups".to_owned()),
			_ => None,
		};
		Arc::new(Store::new(Config::read(env).unwrap()))
	}

	async fn ask(store: Arc<Store>, method: &str, path: &str) -> (StatusCode, serde_json::Value) {
		let request = Request::builder().method(method).uri(path).body(Body::empty()).unwrap();
		let answer = routes(store).oneshot(request).await.unwrap();
		let status = answer.status();
		let body = answer.into_body().collect().await.unwrap().to_bytes();
		(status, serde_json::from_slice(&body).unwrap())
	}

	#[tokio::test]
	async fn healthy_without_a_source_and_the_job_says_why_it_cannot_run() {
		let (status, body) = ask(store(), "GET", "/health").await;
		assert_eq!(status, StatusCode::OK);
		assert_eq!(body["data"]["mirror"], "unconfigured");
		let (status, body) = ask(store(), "POST", "/jobs/mirror").await;
		assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
		assert_eq!(
			body["message"],
			"the backup store is not configured: BACKUP_S3_ENDPOINT is not set"
		);
	}

	#[test]
	fn the_socket_is_the_declared_one() {
		let declared = include_str!("../service.toml");
		assert!(declared.contains(&format!("\nsocket = \"{SOCKET}\"\n")));
		assert!(declared.contains("buckets = [\"backups\"]"));
		for code in response::codes_named(include_str!("api.rs")) {
			assert!(response::message_of(code).is_some(), "{code} is not in the catalogue");
		}
	}
}
