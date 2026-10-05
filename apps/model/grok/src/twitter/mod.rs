//! X data under `/twitter/`, read by the agent with xAI's X tools.
//! spec/architecture/grok/twitter.md.

mod fetch;
mod job;
mod salvage;
mod shape;
mod store;
mod time;

use std::sync::Arc;
use std::time::Duration;

use axum::Router;
use axum::extract::{Path, Query, RawQuery, State};
use axum::http::{HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use serde_json::json;

use crate::config;
use crate::http::AppState;
use crate::turn::Bridge;
use fetch::{Reply, Settings};
use job::{Params, Task};
use store::Store;

/// What a `202` tells a client to wait before asking again: about as long as a fetch takes.
const RETRY_AFTER_SECS: u64 = 10;

pub struct Service {
	bridge: Arc<Bridge>,
	settings: Arc<Settings>,
	fast_response: bool,
	store: Arc<Store>,
}

impl Service {
	pub fn new(bridge: Arc<Bridge>, config: &config::Twitter) -> std::io::Result<Self> {
		let settings = Settings { budget: config.budget, effort: config.effort.clone() };
		let store = Store::new(bridge.environment.twitter.clone())?;
		Ok(Self {
			bridge,
			settings: Arc::new(settings),
			fast_response: config.fast_response,
			store: Arc::new(store),
		})
	}

	/// Forgets the latest results nobody has asked for in a day; run on a timer.
	pub fn sweep(&self) {
		self.store.sweep(Duration::from_secs(24 * 60 * 60));
	}

	async fn serve(&self, key: String, task: Result<Task, String>) -> Response {
		let task = match task {
			Ok(task) => task,
			Err(message) => {
				let body = json!({ "error": { "type": "invalid_request_error", "message": message } });
				return respond(StatusCode::BAD_REQUEST, body, job::NO_STORE, None);
			}
		};
		let latest = self.store.latest(&key);
		// What can no longer change is answered as it was kept, fast response or not.
		if let Some(settled) = latest.as_ref().filter(|reply| reply.is_settled()) {
			return reply_response(settled);
		}
		// Everything else refreshes on every request, one refresh per key at a time.
		let (bridge, settings) = (self.bridge.clone(), self.settings.clone());
		let mut refreshed =
			self.store.refresh(&key, async move { fetch::run(&bridge, &settings, &task).await });
		if self.fast_response {
			return match latest {
				Some(reply) => reply_response(&reply),
				None => {
					let body = json!({ "status": "pending", "retry_after": RETRY_AFTER_SECS });
					respond(StatusCode::ACCEPTED, body, job::NO_STORE, Some(RETRY_AFTER_SECS))
				}
			};
		}
		match refreshed.recv().await {
			Ok(reply) => reply_response(&reply),
			Err(_) => {
				let body = json!({ "error": { "type": "upstream_error", "message": "the fetch ended without an answer" } });
				respond(StatusCode::BAD_GATEWAY, body, job::NO_STORE, None)
			}
		}
	}
}

fn reply_response(reply: &Reply) -> Response {
	respond(reply.status, reply.body.clone(), reply.cache_control, None)
}

fn respond(
	status: StatusCode,
	body: serde_json::Value,
	cache_control: &'static str,
	retry_after: Option<u64>,
) -> Response {
	let mut response = (status, axum::Json(body)).into_response();
	let headers = response.headers_mut();
	headers.insert(header::CACHE_CONTROL, HeaderValue::from_static(cache_control));
	if let Some(seconds) = retry_after {
		headers.insert(header::RETRY_AFTER, HeaderValue::from(seconds));
	}
	response
}

/// The request as a key: its path and its query in a fixed order, so the same question asked with
/// its parameters in another order is the same question.
fn key(path: &str, query: &Option<String>) -> String {
	let mut pairs: Vec<&str> =
		query.as_deref().unwrap_or_default().split('&').filter(|pair| !pair.is_empty()).collect();
	pairs.sort_unstable();
	format!("{path}?{}", pairs.join("&"))
}

pub fn router() -> Router<AppState> {
	Router::new()
		.route("/posts/{id}", get(post))
		.route("/posts/{id}/thread", get(thread))
		.route("/posts/{id}/replies", get(replies))
		.route("/posts/{id}/quotes", get(quotes))
		.route("/posts/{id}/reposts", get(reposts))
		.route("/users/search", get(users))
		.route("/users/{username}", get(user))
		.route("/users/{username}/posts", get(user_posts))
		.route("/users/{username}/media", get(user_media))
		.route("/users/{username}/mentions", get(mentions))
		.route("/search", get(search))
		.route("/search/semantic", get(semantic))
}

macro_rules! endpoint {
	($name:ident, $path:literal, |$id:ident, $params:ident| $task:expr) => {
		async fn $name(
			State(state): State<AppState>,
			Path($id): Path<String>,
			Query($params): Query<Params>,
			RawQuery(raw): RawQuery,
		) -> Response {
			let _ = &$params;
			state.twitter.serve(key(&format!($path, $id), &raw), $task).await
		}
	};
	($name:ident, $path:literal, |$params:ident| $task:expr) => {
		async fn $name(
			State(state): State<AppState>,
			Query($params): Query<Params>,
			RawQuery(raw): RawQuery,
		) -> Response {
			state.twitter.serve(key($path, &raw), $task).await
		}
	};
}

endpoint!(post, "/posts/{}", |id, params| job::post(&id));
endpoint!(thread, "/posts/{}/thread", |id, params| job::thread(&id));
endpoint!(replies, "/posts/{}/replies", |id, params| job::replies(&id, &params));
endpoint!(quotes, "/posts/{}/quotes", |id, params| job::quotes(&id, &params));
endpoint!(reposts, "/posts/{}/reposts", |id, params| job::reposts(&id, &params));
endpoint!(user, "/users/{}", |name, params| job::user(&name));
endpoint!(user_posts, "/users/{}/posts", |name, params| job::user_posts(&name, &params));
endpoint!(user_media, "/users/{}/media", |name, params| job::user_media(&name, &params));
endpoint!(mentions, "/users/{}/mentions", |name, params| job::mentions(&name, &params));
endpoint!(users, "/users/search", |params| job::users(&params));
endpoint!(search, "/search", |params| job::search(&params));
endpoint!(semantic, "/search/semantic", |params| job::semantic(&params));

#[cfg(test)]
mod tests {
	use super::key;

	#[test]
	fn a_key_ignores_parameter_order() {
		assert_eq!(
			key("/search", &Some("q=a&limit=5".into())),
			key("/search", &Some("limit=5&q=a".into()))
		);
		assert_eq!(key("/posts/1", &None), "/posts/1?");
	}
}
