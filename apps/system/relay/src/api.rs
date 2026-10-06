//! What a relay answers: its health, every node at once, a browser's live socket and its
//! neighbors' sockets.

use crate::relay::Relay;
use crate::{live, mesh};
use axum::Router;
use axum::extract::State;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::ws::rejection::WebSocketUpgradeRejection;
use axum::http::{HeaderMap, StatusCode};
use axum::response::Response;
use axum::routing::get;
use std::sync::Arc;

pub fn routes(relay: Arc<Relay>) -> Router {
	Router::new()
		.route("/health", get(health))
		.route("/state", get(state))
		.route("/live", get(watched))
		.route(mesh::PATH, get(neighbor))
		.fallback(|| async { response::failure(StatusCode::NOT_FOUND, "no_such_route") })
		.with_state(relay)
}

/// Healthy once host has been read, or after a grace; see `relay::GRACE`.
async fn health(State(relay): State<Arc<Relay>>) -> Response {
	if relay.healthy() {
		response::success(StatusCode::OK, ())
	} else {
		response::failure(StatusCode::SERVICE_UNAVAILABLE, "upstream_unavailable")
	}
}

async fn state(State(relay): State<Arc<Relay>>) -> Response {
	response::success(StatusCode::OK, relay.state())
}

/// Open, and read-only: Access stands in front of the public name, and the private one admits the
/// LAN and the tailnet alone. See spec/architecture/console.md, "It reads, and does not write, at
/// first".
async fn watched(
	State(relay): State<Arc<Relay>>,
	upgrade: Result<WebSocketUpgrade, WebSocketUpgradeRejection>,
) -> Response {
	let Ok(upgrade) = upgrade else {
		return response::failure(StatusCode::UPGRADE_REQUIRED, "invalid_method");
	};
	upgrade.on_upgrade(|socket| async move {
		if let Err(error) = live::watch(relay, socket).await {
			eprintln!("relay: a browser's socket: {error}");
		}
	})
}

/// A neighbor's relay, which carries the mesh's secret.
async fn neighbor(
	State(relay): State<Arc<Relay>>,
	headers: HeaderMap,
	upgrade: Result<WebSocketUpgrade, WebSocketUpgradeRejection>,
) -> Response {
	if !mesh::admitted(&headers, relay.secret()) {
		return response::failure(StatusCode::UNAUTHORIZED, "invalid_token");
	}
	let Ok(upgrade) = upgrade else {
		return response::failure(StatusCode::UPGRADE_REQUIRED, "invalid_method");
	};
	upgrade.on_upgrade(|socket| async move {
		if let Err(error) = mesh::converse(relay, None, socket).await {
			eprintln!("relay: a neighbor's socket: {error}");
		}
	})
}

#[cfg(test)]
mod tests {
	use super::*;
	use axum::body::Body;
	use axum::http::Request;
	use tower::ServiceExt;

	async fn ask(
		relay: &Arc<Relay>,
		path: &str,
		bearer: Option<&str>,
	) -> (StatusCode, serde_json::Value) {
		let mut request = Request::get(path);
		if let Some(bearer) = bearer {
			request = request.header("authorization", format!("Bearer {bearer}"));
		}
		let request = request.body(Body::empty()).unwrap();
		let response = routes(relay.clone()).oneshot(request).await.unwrap();
		let status = response.status();
		let body = axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap();
		(status, serde_json::from_slice(&body).unwrap())
	}

	#[tokio::test]
	async fn the_mesh_asks_for_the_secret_before_anything_else() {
		let relay = Relay::new("rdu".into(), "s3cret".into());
		for bearer in [None, Some("wrong")] {
			let (status, body) = ask(&relay, mesh::PATH, bearer).await;
			assert_eq!((status, &body["code"]), (StatusCode::UNAUTHORIZED, &"invalid_token".into()));
		}
		// The secret, on a request that is no socket.
		let (status, body) = ask(&relay, mesh::PATH, Some("s3cret")).await;
		assert_eq!((status, &body["code"]), (StatusCode::UPGRADE_REQUIRED, &"invalid_method".into()));
	}

	#[tokio::test]
	async fn health_waits_for_host_and_state_answers_every_node() {
		let relay = Relay::new("rdu".into(), "s3cret".into());
		let (status, body) = ask(&relay, "/health", None).await;
		assert_eq!(status, StatusCode::SERVICE_UNAVAILABLE);
		assert_eq!(body["code"], "upstream_unavailable");

		let machine = Ok(serde_json::json!({}));
		relay.observe(crate::host::Reading { events: Ok(vec![]), apps: Ok(vec![]), machine });
		assert_eq!(ask(&relay, "/health", None).await.0, StatusCode::OK);
		let (status, body) = ask(&relay, "/state", None).await;
		assert_eq!(status, StatusCode::OK);
		assert_eq!((&body["data"]["version"], &body["data"]["node"]), (&1.into(), &"rdu".into()));
		assert!(body["data"]["nodes"]["rdu"]["version"].as_u64().is_some());
		assert!(body["data"]["nodes"]["rdu"]["heard_at"].is_string());
		assert_eq!(body["data"]["nodes"]["rdu"]["snapshot"]["apps"], serde_json::json!([]));
	}

	#[tokio::test]
	async fn anything_else_is_no_route() {
		let relay = Relay::new("rdu".into(), "s3cret".into());
		assert_eq!(ask(&relay, "/", None).await.0, StatusCode::NOT_FOUND);
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
