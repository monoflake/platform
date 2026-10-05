//! The HTTP surface: routing, the key, and what both API shapes share.
//! spec/architecture/grok/api.md.

use std::convert::Infallible;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use axum::extract::{DefaultBodyLimit, Path, Request, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::middleware::{self, Next};
use axum::response::sse::{Event, KeepAlive, Sse};
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use serde_json::Value;
use tokio::sync::mpsc;
use tokio_stream::wrappers::ReceiverStream;

use crate::turn::{self, Bridge, Update};
use crate::{anthropic, openai, responses, twitter};

/// Images arrive inline, so a request can be far larger than axum's 2 MB default.
const BODY_LIMIT: usize = 32 * 1024 * 1024;

#[derive(Clone)]
pub struct AppState {
	pub bridge: Arc<Bridge>,
	pub twitter: Arc<twitter::Service>,
	api_key: Arc<str>,
}

pub fn router(bridge: Arc<Bridge>, twitter: Arc<twitter::Service>, api_key: String) -> Router {
	let state = AppState { bridge, twitter, api_key: api_key.into() };
	Router::new()
		.route("/v1/models", get(models))
		.route("/v1/models/{id}", get(model))
		.route("/v1/chat/completions", post(openai::chat_completions))
		.route("/v1/messages", post(anthropic::messages))
		.route("/v1/responses", post(responses::responses))
		.nest("/twitter", twitter::router())
		.layer(middleware::from_fn_with_state(state.clone(), authorize))
		// Outside the key, so the node can ask whether it is up. See
		// spec/architecture/grok/deployment.md, "The app is grok; the program is grok2api".
		.route("/health", get(health))
		.layer(DefaultBodyLimit::max(BODY_LIMIT))
		.with_state(state)
}

/// Serving, in the platform's envelope.
async fn health() -> Json<Value> {
	Json(serde_json::json!({ "status": "success", "data": null }))
}

/// Which API a request speaks, and so which shape its answer and its errors take.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Dialect {
	OpenAi,
	Anthropic,
}

impl Dialect {
	/// Anthropic's SDKs send `anthropic-version` on every request, `/v1/models` included; that
	/// header is what tells the two apart where the path does not.
	fn of(headers: &HeaderMap, path: &str) -> Self {
		if path == "/v1/messages" || headers.contains_key("anthropic-version") {
			Self::Anthropic
		} else {
			Self::OpenAi
		}
	}
}

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum FailureKind {
	Invalid,
	Unauthorized,
	NotFound,
	Upstream,
}

/// An error, before it is given one API's shape.
#[derive(Debug)]
pub struct Failure {
	pub kind: FailureKind,
	pub message: String,
}

impl Failure {
	pub fn invalid(message: impl Into<String>) -> Self {
		Self { kind: FailureKind::Invalid, message: message.into() }
	}

	pub fn upstream(message: impl Into<String>) -> Self {
		Self { kind: FailureKind::Upstream, message: message.into() }
	}

	pub fn render(self, dialect: Dialect) -> Response {
		let status = match self.kind {
			FailureKind::Invalid => StatusCode::BAD_REQUEST,
			FailureKind::Unauthorized => StatusCode::UNAUTHORIZED,
			FailureKind::NotFound => StatusCode::NOT_FOUND,
			FailureKind::Upstream => StatusCode::BAD_GATEWAY,
		};
		let body = match dialect {
			Dialect::OpenAi => openai::error_body(self.kind, &self.message),
			Dialect::Anthropic => anthropic::error_body(self.kind, &self.message),
		};
		(status, Json(body)).into_response()
	}
}

async fn authorize(State(state): State<AppState>, request: Request, next: Next) -> Response {
	let headers = request.headers();
	let bearer = headers
		.get(header::AUTHORIZATION)
		.and_then(|value| value.to_str().ok())
		.and_then(|value| value.strip_prefix("Bearer "));
	// Anthropic's SDKs send the key as `x-api-key`; OpenAI's as a bearer token.
	let api_key = headers.get("x-api-key").and_then(|value| value.to_str().ok());
	let expected = state.api_key.as_bytes();
	if [bearer, api_key].into_iter().flatten().any(|key| constant_time_eq(key.as_bytes(), expected)) {
		return next.run(request).await;
	}
	let dialect = Dialect::of(headers, request.uri().path());
	Failure { kind: FailureKind::Unauthorized, message: "a valid API key is required".into() }
		.render(dialect)
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
	a.len() == b.len() && a.iter().zip(b).fold(0u8, |diff, (x, y)| diff | (x ^ y)) == 0
}

async fn models(State(state): State<AppState>, headers: HeaderMap) -> Json<Value> {
	let agent = state.bridge.agent();
	Json(match Dialect::of(&headers, "/v1/models") {
		Dialect::OpenAi => openai::model_list(&agent.info.models),
		Dialect::Anthropic => anthropic::model_list(&agent.info.models),
	})
}

async fn model(
	State(state): State<AppState>,
	headers: HeaderMap,
	Path(id): Path<String>,
) -> Response {
	let dialect = Dialect::of(&headers, "/v1/models");
	let agent = state.bridge.agent();
	let Some(model) = agent.info.models.iter().find(|model| model.id == id) else {
		return unknown_model(&id).render(dialect);
	};
	Json(match dialect {
		Dialect::OpenAi => openai::model_object(model),
		Dialect::Anthropic => anthropic::model_object(model),
	})
	.into_response()
}

fn unknown_model(model: &str) -> Failure {
	Failure {
		kind: FailureKind::NotFound,
		message: format!("the model {model} does not exist; see /v1/models"),
	}
}

/// The model a request names, or the agent's default when it names none. One the agent does not
/// offer is refused rather than swapped for another (spec/architecture/grok/api.md).
pub fn resolve_model(bridge: &Bridge, requested: Option<&str>) -> Result<String, Failure> {
	let agent = bridge.agent();
	match requested.filter(|model| !model.is_empty()) {
		None => Ok(agent.info.default_model.clone()),
		Some(model) if agent.info.offers(model) => Ok(model.to_owned()),
		Some(model) => Err(unknown_model(model)),
	}
}

pub async fn start(
	bridge: &Arc<Bridge>,
	request: turn::Request,
) -> Result<mpsc::Receiver<Update>, Failure> {
	bridge.start(request).await.map_err(|error| {
		if error.is::<turn::UnknownReply>() {
			return Failure::invalid(error.to_string());
		}
		tracing::error!(%error, "a completion could not start");
		Failure::upstream(error.to_string())
	})
}

/// Server-sent events fed from a channel. When the client goes away the stream is dropped, the
/// sends into it fail, and the turn is cancelled from there.
pub fn event_stream(rx: mpsc::Receiver<Result<Event, Infallible>>) -> impl IntoResponse {
	Sse::new(ReceiverStream::new(rx)).keep_alive(KeepAlive::default())
}

pub fn now() -> u64 {
	SystemTime::now().duration_since(UNIX_EPOCH).map(|elapsed| elapsed.as_secs()).unwrap_or(0)
}

/// A reply id's random part.
pub fn random_id() -> String {
	uuid::Uuid::new_v4().simple().to_string()
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn anthropic_is_told_by_path_or_header() {
		let mut headers = HeaderMap::new();
		assert_eq!(Dialect::of(&headers, "/v1/models"), Dialect::OpenAi);
		assert_eq!(Dialect::of(&headers, "/v1/messages"), Dialect::Anthropic);
		headers.insert("anthropic-version", "2023-06-01".parse().unwrap());
		assert_eq!(Dialect::of(&headers, "/v1/models"), Dialect::Anthropic);
	}

	#[test]
	fn keys_compare_whole() {
		assert!(constant_time_eq(b"key", b"key"));
		assert!(!constant_time_eq(b"key", b"ke"));
		assert!(!constant_time_eq(b"key", b"kez"));
	}
}
