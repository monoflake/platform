//! `/health`, on the container's own port: `200` while the proxy listens, saying where it sends and
//! what each member last answered. A database without a primary is the database's to report, not
//! the proxy's to fail on.

use crate::state::State;
use axum::Router;
use axum::extract::State as Shared;
use axum::http::StatusCode;
use axum::response::Response;
use axum::routing::get;
use std::sync::Arc;

pub fn routes(state: Arc<State>) -> Router {
	Router::new()
		.route("/health", get(health))
		.fallback(|| async { response::failure(StatusCode::NOT_FOUND, "no_such_route") })
		.with_state(state)
}

async fn health(Shared(state): Shared<Arc<State>>) -> Response {
	let target = serde_json::to_value(state.target()).unwrap_or_default();
	response::success(
		StatusCode::OK,
		serde_json::json!({ "routing": target, "members": state.members() }),
	)
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::config::Member;
	use axum::body::Body;
	use axum::http::Request;
	use http_body_util::BodyExt;
	use tower::ServiceExt;

	#[tokio::test]
	async fn healthy_with_no_primary_and_saying_so() {
		let member = Member { name: "tyo".into(), host: "tyo.test".into(), rest: 8008, postgres: 5432 };
		let routes = routes(Arc::new(State::new(&[member])));
		let answer =
			routes.oneshot(Request::get("/health").body(Body::empty()).unwrap()).await.unwrap();
		assert_eq!(answer.status(), StatusCode::OK);
		let body: serde_json::Value =
			serde_json::from_slice(&answer.into_body().collect().await.unwrap().to_bytes()).unwrap();
		assert_eq!(body["data"]["routing"]["target"], "none");
		assert_eq!(body["data"]["members"]["tyo"]["up"], false);
	}

	#[test]
	fn every_code_it_answers_with_is_in_the_catalogue() {
		for code in response::codes_named(include_str!("api.rs")) {
			assert!(response::message_of(code).is_some(), "{code} is not in the catalogue");
		}
	}
}
