//! OpenAI's Chat Completions shape; spec/architecture/grok/api.md.

use std::convert::Infallible;

use axum::Json;
use axum::extract::State;
use axum::response::sse::Event;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};
use tokio::sync::mpsc;

use crate::agent::Model;
use crate::http::{self, AppState, Dialect, Failure, FailureKind};
use crate::message;
use crate::turn::{self, Outcome, Update, Usage};

pub async fn chat_completions(State(state): State<AppState>, Json(body): Json<Value>) -> Response {
	match answer(&state, &body).await {
		Ok(response) => response,
		Err(failure) => failure.render(Dialect::OpenAi),
	}
}

async fn answer(state: &AppState, body: &Value) -> Result<Response, Failure> {
	// Everything else a client may send and the agent cannot honor is ignored; `n` alone changes
	// the response's shape (spec/architecture/grok/api.md).
	if body["n"].as_u64().is_some_and(|n| n > 1) {
		return Err(Failure::invalid("n greater than 1 is not supported"));
	}
	let messages =
		body["messages"].as_array().ok_or_else(|| Failure::invalid("messages is required"))?;
	let conversation = message::parse_openai(messages).map_err(Failure::invalid)?;
	let model = http::resolve_model(&state.bridge, body["model"].as_str())?;
	let id = format!("chatcmpl-{}", http::random_id());
	let request = turn::Request {
		conversation,
		model: model.clone(),
		effort: body["reasoning_effort"].as_str().map(str::to_owned),
		schema: schema(&body["response_format"]),
		reply_id: id.clone(),
		previous: None,
	};
	let mut updates = http::start(&state.bridge, request).await?;
	let head = Head { id, created: http::now(), model };
	if body["stream"].as_bool().unwrap_or(false) {
		let include_usage = body["stream_options"]["include_usage"].as_bool().unwrap_or(false);
		return Ok(streamed(Chunks { head, include_usage }, updates).into_response());
	}
	let mut collected = Vec::new();
	while let Some(update) = updates.recv().await {
		collected.push(update);
	}
	Ok(Json(assemble(&head, collected)?).into_response())
}

/// `response_format` as the schema the agent takes: `json_schema` as given, `json_object` as any
/// object, `text` as none.
fn schema(format: &Value) -> Option<Value> {
	match format["type"].as_str() {
		Some("json_schema") => format["json_schema"].get("schema").cloned(),
		Some("json_object") => Some(json!({ "type": "object" })),
		_ => None,
	}
}

pub struct Head {
	pub id: String,
	pub created: u64,
	pub model: String,
}

/// The whole reply to a request that did not stream.
pub fn assemble(head: &Head, updates: Vec<Update>) -> Result<Value, Failure> {
	let (mut content, mut reasoning) = (String::new(), String::new());
	for update in updates {
		match update {
			Update::Content(text) => content.push_str(&text),
			Update::Reasoning(text) => reasoning.push_str(&text),
			Update::Done(Outcome { stop_reason, usage }) => {
				let mut message = json!({ "role": "assistant", "content": content });
				if !reasoning.is_empty() {
					message["reasoning_content"] = reasoning.into();
				}
				return Ok(json!({
					"id": head.id,
					"object": "chat.completion",
					"created": head.created,
					"model": head.model,
					"choices": [{ "index": 0, "message": message, "finish_reason": finish_reason(&stop_reason) }],
					"usage": usage_body(usage),
				}));
			}
			Update::Failed(message) => return Err(Failure::upstream(message)),
		}
	}
	Err(Failure::upstream("the turn ended without an answer"))
}

/// Renders a turn's updates as `chat.completion.chunk` objects.
pub struct Chunks {
	pub head: Head,
	pub include_usage: bool,
}

impl Chunks {
	fn chunk(&self, delta: Value, finish_reason: Value) -> Value {
		json!({
			"id": self.head.id,
			"object": "chat.completion.chunk",
			"created": self.head.created,
			"model": self.head.model,
			"choices": [{ "index": 0, "delta": delta, "finish_reason": finish_reason }],
		})
	}

	/// The chunk every stream opens with, naming the role.
	pub fn opening(&self) -> Value {
		self.chunk(json!({ "role": "assistant", "content": "" }), Value::Null)
	}

	/// The chunks one update becomes, and whether the stream ends with them.
	pub fn render(&self, update: Update) -> (Vec<Value>, bool) {
		match update {
			Update::Content(text) => (vec![self.chunk(json!({ "content": text }), Value::Null)], false),
			Update::Reasoning(text) => {
				(vec![self.chunk(json!({ "reasoning_content": text }), Value::Null)], false)
			}
			Update::Done(Outcome { stop_reason, usage }) => {
				let mut chunks = vec![self.chunk(json!({}), finish_reason(&stop_reason).into())];
				if self.include_usage {
					let mut last = self.chunk(json!({}), Value::Null);
					last["choices"] = json!([]);
					last["usage"] = usage_body(usage);
					chunks.push(last);
				}
				(chunks, true)
			}
			Update::Failed(message) => (vec![error_body(FailureKind::Upstream, &message)], true),
		}
	}
}

fn streamed(chunks: Chunks, mut updates: mpsc::Receiver<Update>) -> impl IntoResponse {
	let (tx, rx) = mpsc::channel::<Result<Event, Infallible>>(64);
	tokio::spawn(async move {
		let send = |value: Value| {
			let tx = tx.clone();
			async move { tx.send(Ok(Event::default().data(value.to_string()))).await.is_ok() }
		};
		if !send(chunks.opening()).await {
			return;
		}
		while let Some(update) = updates.recv().await {
			let (values, done) = chunks.render(update);
			for value in values {
				if !send(value).await {
					return;
				}
			}
			if done {
				break;
			}
		}
		let _ = tx.send(Ok(Event::default().data("[DONE]"))).await;
	});
	http::event_stream(rx)
}

fn finish_reason(stop_reason: &str) -> &'static str {
	match stop_reason {
		"max_tokens" => "length",
		"refusal" => "content_filter",
		_ => "stop",
	}
}

/// OpenAI's `prompt_tokens` includes the cached part, as ACP's `inputTokens` does.
fn usage_body(usage: Usage) -> Value {
	json!({
		"prompt_tokens": usage.input,
		"completion_tokens": usage.output,
		"total_tokens": usage.input + usage.output,
		"prompt_tokens_details": { "cached_tokens": usage.cache_read },
		"completion_tokens_details": { "reasoning_tokens": usage.reasoning },
	})
}

pub fn error_body(kind: FailureKind, message: &str) -> Value {
	let (kind, code) = match kind {
		FailureKind::Invalid => ("invalid_request_error", None),
		FailureKind::Unauthorized => ("invalid_request_error", Some("invalid_api_key")),
		FailureKind::NotFound => ("invalid_request_error", Some("model_not_found")),
		FailureKind::Upstream => ("api_error", None),
	};
	json!({ "error": { "message": message, "type": kind, "param": null, "code": code } })
}

pub fn model_object(model: &Model) -> Value {
	json!({ "id": model.id, "object": "model", "created": 0, "owned_by": "xai" })
}

pub fn model_list(models: &[Model]) -> Value {
	json!({ "object": "list", "data": models.iter().map(model_object).collect::<Vec<_>>() })
}

#[cfg(test)]
mod tests {
	use super::*;

	fn head() -> Head {
		Head { id: "chatcmpl-1".into(), created: 1, model: "grok-4.7".into() }
	}

	fn done() -> Update {
		let usage = Usage { input: 100, output: 10, cache_read: 40, cache_creation: 0, reasoning: 4 };
		Update::Done(Outcome { stop_reason: "end_turn".into(), usage })
	}

	#[test]
	fn a_whole_reply_carries_reasoning_and_usage() {
		let reply = assemble(
			&head(),
			vec![
				Update::Reasoning("hm".into()),
				Update::Content("Hi".into()),
				Update::Content("!".into()),
				done(),
			],
		)
		.unwrap();
		let choice = &reply["choices"][0];
		assert_eq!(choice["message"]["content"], "Hi!");
		assert_eq!(choice["message"]["reasoning_content"], "hm");
		assert_eq!(choice["finish_reason"], "stop");
		assert_eq!(reply["usage"]["prompt_tokens"], 100);
		assert_eq!(reply["usage"]["total_tokens"], 110);
		assert_eq!(reply["usage"]["prompt_tokens_details"]["cached_tokens"], 40);
	}

	#[test]
	fn no_reasoning_means_no_field() {
		let reply = assemble(&head(), vec![Update::Content("Hi".into()), done()]).unwrap();
		assert!(reply["choices"][0]["message"].get("reasoning_content").is_none());
	}

	#[test]
	fn a_failed_turn_is_an_upstream_error() {
		let failure = assemble(&head(), vec![Update::Failed("gone".into())]).unwrap_err();
		assert_eq!(failure.kind, FailureKind::Upstream);
	}

	#[test]
	fn the_stream_ends_with_finish_then_usage() {
		let chunks = Chunks { head: head(), include_usage: true };
		assert_eq!(chunks.opening()["choices"][0]["delta"]["role"], "assistant");
		let (values, done_now) = chunks.render(Update::Reasoning("hm".into()));
		assert_eq!(values[0]["choices"][0]["delta"]["reasoning_content"], "hm");
		assert!(!done_now);
		let (values, done_now) = chunks.render(done());
		assert!(done_now);
		assert_eq!(values[0]["choices"][0]["finish_reason"], "stop");
		assert_eq!(values[1]["choices"], json!([]));
		assert_eq!(values[1]["usage"]["completion_tokens"], 10);
	}

	#[test]
	fn stop_reasons() {
		assert_eq!(finish_reason("max_tokens"), "length");
		assert_eq!(finish_reason("refusal"), "content_filter");
		assert_eq!(finish_reason("end_turn"), "stop");
	}

	#[test]
	fn response_formats() {
		let schema = json!({ "type": "object", "properties": { "a": { "type": "string" } } });
		let format = json!({ "type": "json_schema", "json_schema": { "name": "x", "schema": schema } });
		assert_eq!(super::schema(&format), Some(schema));
		assert_eq!(super::schema(&json!({ "type": "json_object" })), Some(json!({ "type": "object" })));
		assert_eq!(super::schema(&json!({ "type": "text" })), None);
		assert_eq!(super::schema(&Value::Null), None);
	}
}
