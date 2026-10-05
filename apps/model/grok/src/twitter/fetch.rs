//! Running one task against the agent, within the time budget. spec/architecture/grok/twitter.md.

use std::time::Duration;

use axum::http::StatusCode;
use serde_json::{Value, json};
use tokio::time::Instant;

use super::job::{self, Keyword, Mode, Task};
use super::{salvage, shape, time};
use crate::agent::Agent;
use crate::environment::Profile;
use crate::turn::Bridge;

/// What every X session is told. The tool results reach only the model, so the model's copy is the
/// data; it is asked to copy, not to describe.
const SYSTEM: &str = "You read X with your X tools and report what they return. Copy ids, handles, \
	names, text and URLs exactly, character for character. Write timestamps as ISO 8601 UTC, like \
	2026-09-27T08:55:36Z. Never add, guess or invent anything: report only what a tool returned.";

/// How long a cancelled turn is given to stop and hand back what it wrote.
const GRACE: Duration = Duration::from_secs(10);

pub struct Settings {
	pub budget: Duration,
	pub effort: String,
}

/// A finished request: what to send, and how long it may be kept.
#[derive(Debug)]
pub struct Reply {
	pub status: StatusCode,
	pub body: Value,
	pub cache_control: &'static str,
}

impl Reply {
	fn error(status: StatusCode, kind: &str, message: impl Into<String>) -> Self {
		Self {
			status,
			body: json!({ "error": { "type": kind, "message": message.into() } }),
			cache_control: job::NO_STORE,
		}
	}

	fn data(task: &Task, data: Value, meta: Value) -> Self {
		let cache_control = task.cache_control(&data, time::now());
		let mut body = json!({ "data": data, "meta": meta });
		body["meta"]["fetched_at"] = time::format_timestamp(time::now()).into();
		Self { status: StatusCode::OK, body, cache_control }
	}

	fn not_found(message: impl Into<String>) -> Self {
		// That a post or user is absent is itself worth keeping for a while.
		Self { cache_control: job::RECENT, ..Self::error(StatusCode::NOT_FOUND, "not_found", message) }
	}

	/// Whether it can no longer change, and so is kept and never fetched again
	/// (spec/architecture/grok/twitter.md).
	pub fn is_settled(&self) -> bool {
		self.status == StatusCode::OK && self.cache_control == job::IMMUTABLE
	}

	/// Whether it may replace an earlier answer to the same request. A failure may not: an answer
	/// that was right a minute ago is a better one to give than an error.
	pub fn is_answer(&self) -> bool {
		self.status.is_success() || self.status == StatusCode::NOT_FOUND
	}
}

#[derive(Debug, PartialEq)]
enum Ended {
	Done,
	OutOfTime,
	Failed(String),
}

pub async fn run(bridge: &Bridge, settings: &Settings, task: &Task) -> Reply {
	let agent = bridge.agent();
	let session =
		match agent.new_session(&bridge.environment.workspace, Profile::Twitter, SYSTEM).await {
			Ok(session) => session,
			Err(error) => {
				return Reply::error(StatusCode::BAD_GATEWAY, "upstream_error", error.to_string());
			}
		};
	// The standard model, never the fast one (spec/architecture/grok/twitter.md).
	let model = agent.info.default_model.clone();
	let _ = agent.set_option(&session, "model", &model).await;
	let _ = agent.set_option(&session, "reasoning_effort", &settings.effort).await;
	let deadline = Instant::now() + settings.budget;
	let reply = answer(&agent, &session, task, deadline).await;
	tracing::info!(session, status = reply.status.as_u16(), ?task, "twitter");
	let closing = agent.clone();
	tokio::spawn(async move { closing.close(&session).await });
	reply
}

async fn answer(agent: &Agent, session: &str, task: &Task, deadline: Instant) -> Reply {
	if let Task::Keyword(search) = task {
		return posts(agent, session, task, search, deadline).await;
	}
	let (text, ended) = ask(agent, session, task.prompt(None), &task.schema(), deadline).await;
	if let Ended::Failed(message) = &ended {
		return Reply::error(StatusCode::BAD_GATEWAY, "upstream_error", message.clone());
	}
	let complete = ended == Ended::Done;
	let parsed: Option<Value> = serde_json::from_str(&text).ok();
	match task {
		Task::Semantic { .. } => {
			let items = match &parsed {
				Some(value) => value["posts"].as_array().cloned().unwrap_or_default(),
				None => salvage::complete_items(&text, "posts"),
			};
			list(task, items.iter().filter_map(shape::post).collect(), complete, None)
		}
		Task::Users { .. } => {
			let items = match &parsed {
				Some(value) => value["users"].as_array().cloned().unwrap_or_default(),
				None => salvage::complete_items(&text, "users"),
			};
			list(task, items.iter().filter_map(shape::user).collect(), complete, None)
		}
		_ => {
			let Some(value) = parsed else { return out_of_time_or_garbled(complete) };
			single(task, &value)
		}
	}
}

fn out_of_time_or_garbled(complete: bool) -> Reply {
	if complete {
		Reply::error(
			StatusCode::BAD_GATEWAY,
			"upstream_error",
			"the agent's answer was not the shape asked for",
		)
	} else {
		Reply::error(
			StatusCode::GATEWAY_TIMEOUT,
			"timeout",
			"nothing was obtained within the time budget",
		)
	}
}

fn single(task: &Task, value: &Value) -> Reply {
	match task {
		Task::Post { id } => {
			if value["found"] == false || value["post"].is_null() {
				return Reply::not_found(format!("post {id} was not found"));
			}
			match shape::post(&value["post"]) {
				Some(post) if post["id"] == id.as_str() => {
					Reply::data(task, post, json!({ "complete": true }))
				}
				Some(post) => Reply::error(
					StatusCode::BAD_GATEWAY,
					"upstream_error",
					format!("asked for post {id}, the agent reported {}", post["id"]),
				),
				None => Reply::error(
					StatusCode::BAD_GATEWAY,
					"upstream_error",
					"the agent reported a post that did not check out",
				),
			}
		}
		Task::Thread { id } => {
			if value["found"] == false || value["post"].is_null() {
				return Reply::not_found(format!("post {id} was not found"));
			}
			let Some(post) = shape::post(&value["post"]) else {
				return Reply::error(
					StatusCode::BAD_GATEWAY,
					"upstream_error",
					"the agent reported a post that did not check out",
				);
			};
			let posts = |name: &str| -> Vec<Value> {
				value[name]
					.as_array()
					.map(|items| items.iter().filter_map(shape::post).collect())
					.unwrap_or_default()
			};
			let data = json!({ "post": post, "parents": posts("parents"), "replies": posts("replies") });
			Reply::data(task, data, json!({ "complete": true }))
		}
		Task::User { username } => {
			let user = shape::user(&value["user"]).filter(|user| {
				user["username"].as_str().is_some_and(|name| name.eq_ignore_ascii_case(username))
			});
			match user {
				Some(user) if value["found"] != false => {
					Reply::data(task, user, json!({ "complete": true }))
				}
				_ => Reply::not_found(format!("user @{username} was not found")),
			}
		}
		_ => unreachable!("lists are answered by list"),
	}
}

fn list(task: &Task, items: Vec<Value>, complete: bool, next_cursor: Option<String>) -> Reply {
	if items.is_empty() && !complete {
		return out_of_time_or_garbled(false);
	}
	let meta = json!({ "count": items.len(), "complete": complete, "next_cursor": next_cursor });
	Reply::data(task, Value::Array(items), meta)
}

/// A search, paged ten at a time along `max_id:` while there is more to get and time to get it
/// (spec/architecture/grok/twitter.md, "Pages are grok2api's").
async fn posts(
	agent: &Agent,
	session: &str,
	task: &Task,
	search: &Keyword,
	deadline: Instant,
) -> Reply {
	let schema = task.schema();
	let mut found: Vec<Value> = Vec::new();
	let mut cursor = search.cursor;
	loop {
		let wanted = (search.limit - found.len()).min(job::PAGE);
		let (text, ended) =
			ask(agent, session, task.prompt(Some((wanted, cursor))), &schema, deadline).await;
		if let Ended::Failed(message) = &ended {
			if found.is_empty() {
				return Reply::error(StatusCode::BAD_GATEWAY, "upstream_error", message.clone());
			}
			return list(task, found, false, cursor.map(|cursor| cursor.to_string()));
		}
		let items = match serde_json::from_str::<Value>(&text) {
			Ok(value) => value["posts"].as_array().cloned().unwrap_or_default(),
			Err(_) => salvage::complete_items(&text, "posts"),
		};
		let returned = items.len();
		for post in items.iter().filter_map(shape::post) {
			let id = post["id"].as_str().unwrap_or_default().to_owned();
			let below = |bound: u128| id.parse::<u128>().is_ok_and(|id| id <= bound);
			let seen = found.iter().any(|kept| kept["id"] == id.as_str());
			if !seen && search.skip.as_deref() != Some(id.as_str()) && cursor.is_none_or(below) {
				found.push(post);
			}
		}
		found.truncate(search.limit);
		let lowest = found.iter().filter_map(|post| post["id"].as_str()?.parse::<u128>().ok()).min();
		let next = lowest.map(|lowest| lowest.saturating_sub(1));
		if ended == Ended::OutOfTime {
			return list(task, found, false, next.or(cursor).map(|cursor| cursor.to_string()));
		}
		let exhausted = returned < wanted || next.is_none() || next == cursor;
		if search.mode == Mode::Top || exhausted {
			return list(task, found, true, None);
		}
		if found.len() >= search.limit {
			return list(task, found, true, next.map(|next| next.to_string()));
		}
		cursor = next;
	}
}

/// One prompt in the session, its answer collected as it streams, cut off at the deadline. What was
/// written by then comes back with `OutOfTime`.
async fn ask(
	agent: &Agent,
	session: &str,
	prompt: String,
	schema: &Value,
	deadline: Instant,
) -> (String, Ended) {
	let mut updates = agent.subscribe(session);
	let blocks = vec![json!({ "type": "text", "text": prompt })];
	let call = agent.prompt(session, blocks, Some(schema));
	tokio::pin!(call);
	let mut text = String::new();
	let mut cancelled_at: Option<Instant> = None;
	let result = loop {
		let grace = cancelled_at.map(|at| at + GRACE).unwrap_or(deadline + GRACE);
		tokio::select! {
			result = &mut call => break Some(result),
			Some(update) = updates.recv() => {
				if update["sessionUpdate"] == "agent_message_chunk" {
					text.push_str(update["content"]["text"].as_str().unwrap_or_default());
				}
			}
			_ = tokio::time::sleep_until(deadline), if cancelled_at.is_none() => {
				agent.cancel(session);
				cancelled_at = Some(Instant::now());
			}
			_ = tokio::time::sleep_until(grace), if cancelled_at.is_some() => break None,
		}
	};
	while let Ok(update) = updates.try_recv() {
		if update["sessionUpdate"] == "agent_message_chunk" {
			text.push_str(update["content"]["text"].as_str().unwrap_or_default());
		}
	}
	agent.unsubscribe(session);
	let ended = match result {
		_ if cancelled_at.is_some() => Ended::OutOfTime,
		Some(Ok(result)) if result["stopReason"] == "cancelled" => Ended::OutOfTime,
		Some(Ok(_)) => Ended::Done,
		Some(Err(error)) => Ended::Failed(error.to_string()),
		None => Ended::OutOfTime,
	};
	(text, ended)
}
