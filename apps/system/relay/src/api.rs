//! What a relay answers: its health, every node at once, every node's runs and history, a
//! browser's live socket and its neighbors' sockets.

use crate::history::answer::Asked;
use crate::relay::Relay;
use crate::{live, mesh};
use axum::Router;
use axum::extract::rejection::QueryRejection;
use axum::extract::ws::WebSocketUpgrade;
use axum::extract::ws::rejection::WebSocketUpgradeRejection;
use axum::extract::{Query, State};
use axum::http::header::ORIGIN;
use axum::http::{HeaderMap, StatusCode};
use axum::response::Response;
use axum::routing::get;
use serde::Deserialize;
use std::sync::Arc;
use tower_http::compression::CompressionLayer;

/// The answers compressed as the reader accepts, gzip or brotli: `/runs` is hundreds of kilobytes,
/// more than a far node sends plain inside the console's wait. The sockets are not wrapped.
pub fn routes(relay: Arc<Relay>) -> Router {
	let answers = Router::new()
		.route("/health", get(health))
		.route("/state", get(state))
		.route("/runs", get(runs))
		.route("/history", get(history))
		.layer(CompressionLayer::new().gzip(true).br(true).no_deflate().no_zstd());
	Router::new()
		.merge(answers)
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

/// `/runs`'s query: rows from a moment, in milliseconds, and lean of what no count reads.
#[derive(Deserialize, Default)]
struct Listed {
	since: Option<i64>,
	#[serde(default)]
	lean: bool,
}

/// Read-only and with no token, as `/state` is; answered from the file and the window, never by
/// asking host or a neighbor. See spec/architecture/relay.md, "The runs, mirrored on every relay's
/// disk".
async fn runs(
	State(relay): State<Arc<Relay>>,
	query: Result<Query<Listed>, QueryRejection>,
) -> Response {
	let Ok(Query(Listed { since, lean })) = query else {
		return response::failure(StatusCode::BAD_REQUEST, "invalid_range");
	};
	match relay.runs(since, lean).await {
		Ok(runs) => response::success(StatusCode::OK, runs),
		Err(error) => {
			eprintln!("relay: reading the runs: {error}");
			response::failure(StatusCode::SERVICE_UNAVAILABLE, "store_unavailable")
		}
	}
}

/// `/history`'s query, in seconds.
#[derive(Deserialize)]
struct Spanned {
	span: u64,
	slot: u64,
}

/// Read-only and with no token, as `/runs` is, and answered from the file the same way. See
/// spec/architecture/relay.md, "Each node's minutes, kept for a year".
async fn history(
	State(relay): State<Arc<Relay>>,
	query: Result<Query<Spanned>, QueryRejection>,
) -> Response {
	let asked = query.ok().and_then(|Query(Spanned { span, slot })| Asked::new(span, slot));
	let Some(asked) = asked else {
		return response::failure(StatusCode::BAD_REQUEST, "invalid_series");
	};
	match relay.history(asked).await {
		Ok(history) => response::success(StatusCode::OK, history),
		Err(error) => {
			eprintln!("relay: reading the history: {error}");
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
	async fn runs_answer_from_a_moment_with_what_still_runs_and_lean_of_what_no_count_reads() {
		let relay = relay("rdu");
		let now = jiff::Timestamp::now();
		let ago = |hours: i64| (now - jiff::SignedDuration::from_hours(hours)).to_string();
		let event = |id: i64, outcome: &str, started_at: String| crate::host::Event {
			id,
			app: "geo".into(),
			action: "deploy".into(),
			source: crate::host::Source { kind: "run".into(), run: Some(7), commit: Some("abc".into()) },
			image: Some("ghcr.io/x/geo:1".into()),
			outcome: outcome.into(),
			stage: Some("loading".into()),
			detail: Some("why".into()),
			started_at,
			finished_at: None,
		};
		// A day and a half ago, one done and one that hangs on; an hour ago, one that failed.
		let events = vec![
			event(1, "succeeded", ago(36)),
			event(2, "running", ago(36)),
			event(3, "failed", ago(1)),
		];
		let machine = Ok(serde_json::json!({}));
		relay.observe(crate::host::Reading { events: Ok(events), apps: Ok(vec![]), machine });

		let ids = |body: &serde_json::Value| -> Vec<i64> {
			body["data"]["runs"]
				.as_array()
				.unwrap()
				.iter()
				.map(|row| row["id"].as_i64().unwrap())
				.collect()
		};
		let (_, every) = ask(&relay, "/runs", None).await;
		assert_eq!(ids(&every), vec![3, 2, 1]);
		let day = (now - jiff::SignedDuration::from_hours(24)).as_millisecond();
		let (status, since) = ask(&relay, &format!("/runs?since={day}"), None).await;
		assert_eq!((status, ids(&since)), (StatusCode::OK, vec![3, 2]));

		let (_, lean) = ask(&relay, &format!("/runs?since={day}&lean=true"), None).await;
		let rows = lean["data"]["runs"].as_array().unwrap();
		for row in rows {
			assert!(row.get("image").is_none() && row.get("stage").is_none());
			assert_eq!(row["source"], serde_json::json!({ "kind": "run", "run": 7 }));
		}
		assert_eq!((&rows[0]["detail"], rows[1].get("detail")), (&"why".into(), None));

		let (status, body) = ask(&relay, "/runs?since=soon", None).await;
		assert_eq!((status, &body["code"]), (StatusCode::BAD_REQUEST, &"invalid_range".into()));
	}

	#[tokio::test]
	async fn history_answers_every_node_and_refuses_a_span_it_cannot_cut() {
		let relay = relay("rdu");
		let (status, body) = ask(&relay, "/history?span=86400&slot=3600", None).await;
		assert_eq!(status, StatusCode::OK);
		let data = &body["data"];
		assert_eq!(
			(&data["version"], &data["node"], &data["slot"]),
			(&1.into(), &"rdu".into(), &3600.into())
		);
		assert!(data["from"].is_string() && data["until"].is_string());
		assert_eq!(data["nodes"], serde_json::json!({}));
		for path in
			["/history", "/history?span=86400", "/history?span=a&slot=60", "/history?span=90&slot=60"]
		{
			let (status, body) = ask(&relay, path, None).await;
			assert_eq!(
				(status, &body["code"]),
				(StatusCode::BAD_REQUEST, &"invalid_series".into()),
				"{path}"
			);
		}
	}

	#[tokio::test]
	async fn an_answer_is_compressed_when_the_reader_accepts_it_and_plain_when_not() {
		let relay = relay("rdu");
		let request = |encoding: Option<&str>| {
			let mut request = Request::get("/runs");
			if let Some(encoding) = encoding {
				request = request.header("accept-encoding", encoding);
			}
			request.body(Body::empty()).unwrap()
		};
		for (accepted, encoding) in [("gzip", "gzip"), ("br", "br")] {
			let response = routes(relay.clone()).oneshot(request(Some(accepted))).await.unwrap();
			assert_eq!(response.headers()["content-encoding"], encoding);
			let body = axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap();
			assert!(serde_json::from_slice::<serde_json::Value>(&body).is_err());
			if encoding == "gzip" {
				assert_eq!(body[..2], [0x1f, 0x8b]);
			}
		}
		let response = routes(relay.clone()).oneshot(request(None)).await.unwrap();
		assert!(response.headers().get("content-encoding").is_none());
		let body = axum::body::to_bytes(response.into_body(), usize::MAX).await.unwrap();
		let plain: serde_json::Value = serde_json::from_slice(&body).unwrap();
		assert_eq!(plain["data"]["runs"], serde_json::json!([]));
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
