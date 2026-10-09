//! What a relay answers: its health, every node at once, every node's runs, a browser's live
//! socket and its neighbors' sockets.

use crate::relay::Relay;
use crate::{live, mesh};
use axum::Router;
use axum::extract::State;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::ws::rejection::WebSocketUpgradeRejection;
use axum::http::header::ORIGIN;
use axum::http::{HeaderMap, StatusCode};
use axum::response::Response;
use axum::routing::get;
use std::sync::Arc;

pub fn routes(relay: Arc<Relay>) -> Router {
	Router::new()
		.route("/health", get(health))
		.route("/state", get(state))
		.route("/runs", get(runs))
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

/// Read-only and with no token, as `/state` is; answered from the file and the window, never by
/// asking host or a neighbor. See spec/architecture/relay.md, "The runs, mirrored on every relay's
/// disk".
async fn runs(State(relay): State<Arc<Relay>>) -> Response {
	match relay.runs().await {
		Ok(runs) => response::success(StatusCode::OK, runs),
		Err(error) => {
			eprintln!("relay: reading the runs: {error}");
			response::failure(StatusCode::SERVICE_UNAVAILABLE, "store_unavailable")
		}
	}
}

/// Read-only, with no token: Access stands in front of the public name, and the private one admits
/// the LAN and the tailnet alone. See spec/architecture/console.md, "It reads, and does not write,
/// at first". What Access cannot tell, a page elsewhere opening it with the reader's cookie, the
/// `Origin` does.
async fn watched(
	State(relay): State<Arc<Relay>>,
	headers: HeaderMap,
	upgrade: Result<WebSocketUpgrade, WebSocketUpgradeRejection>,
) -> Response {
	let origin = headers.get(ORIGIN).map(|value| value.to_str().unwrap_or_default());
	if !live::admitted(origin) {
		return response::failure(StatusCode::FORBIDDEN, "invalid_address");
	}
	let Ok(upgrade) = upgrade else {
		return response::failure(StatusCode::UPGRADE_REQUIRED, "invalid_method");
	};
	upgrade.on_upgrade(|socket| async move {
		if let Err(error) = live::watch(relay, socket).await {
			eprintln!("relay: a browser's socket: {error}");
		}
	})
}

/// A neighbor's relay, which carries the mesh's secret; no `Origin` is read, since no page has it.
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

	fn relay(node: &str) -> Arc<Relay> {
		Relay::new(
			node.into(),
			"s3cret".into(),
			Default::default(),
			crate::runs::Store::memory().unwrap(),
		)
		.unwrap()
	}

	async fn ask(
		relay: &Arc<Relay>,
		path: &str,
		bearer: Option<&str>,
	) -> (StatusCode, serde_json::Value) {
		let bearer = bearer.map(|bearer| ("authorization", format!("Bearer {bearer}")));
		asked(relay, path, bearer).await
	}

	async fn asked(
		relay: &Arc<Relay>,
		path: &str,
		header: Option<(&str, String)>,
	) -> (StatusCode, serde_json::Value) {
		let mut request = Request::get(path);
		if let Some((name, value)) = header {
			request = request.header(name, value);
		}
		let request = request.body(Body::empty()).unwrap();
		let response = routes(relay.clone()).oneshot(request).await.unwrap();
		let status = response.status();
		let body = axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap();
		(status, serde_json::from_slice(&body).unwrap())
	}

	#[tokio::test]
	async fn the_mesh_asks_for_the_secret_before_anything_else() {
		let relay = relay("rdu");
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
		let relay = relay("rdu");
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
	async fn runs_answers_every_nodes_rows_with_their_node() {
		let relay = relay("rdu");
		let (status, body) = ask(&relay, "/runs", None).await;
		assert_eq!(status, StatusCode::OK);
		assert_eq!(body["data"], serde_json::json!({ "version": 1, "node": "rdu", "runs": [] }));

		let started_at = jiff::Timestamp::now().to_string();
		let event = crate::host::Event {
			id: 42,
			app: "geo".into(),
			action: "deploy".into(),
			source: crate::host::Source { kind: "panel".into(), run: None, commit: None },
			image: None,
			outcome: "running".into(),
			stage: Some("loading".into()),
			detail: None,
			started_at: started_at.clone(),
			finished_at: None,
		};
		let machine = Ok(serde_json::json!({}));
		relay.observe(crate::host::Reading { events: Ok(vec![event]), apps: Ok(vec![]), machine });
		let (_, body) = ask(&relay, "/runs", None).await;
		assert_eq!(
			body["data"]["runs"],
			serde_json::json!([{ "node": "rdu", "id": 42, "app": "geo", "action": "deploy",
				"source": { "kind": "panel" }, "outcome": "running", "stage": "loading",
				"started_at": started_at }])
		);
	}

	#[tokio::test]
	async fn a_page_elsewhere_cannot_open_the_live_socket() {
		let relay = relay("rdu");
		let foreign = Some(("origin", "https://evil.test".to_owned()));
		let (status, body) = asked(&relay, "/live", foreign).await;
		assert_eq!((status, &body["code"]), (StatusCode::FORBIDDEN, &"invalid_address".into()));
		// The app's own page, and no page at all, reach the upgrade.
		let own = Some(("origin", monoflake::INTERNAL_APP.to_owned()));
		for header in [own, None] {
			assert_eq!(asked(&relay, "/live", header).await.0, StatusCode::UPGRADE_REQUIRED);
		}
	}

	#[tokio::test]
	async fn anything_else_is_no_route() {
		let relay = relay("rdu");
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
