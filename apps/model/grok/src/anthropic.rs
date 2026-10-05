//! Anthropic's Messages shape; spec/architecture/grok/api.md.

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

pub async fn messages(State(state): State<AppState>, Json(body): Json<Value>) -> Response {
	match answer(&state, &body).await {
		Ok(response) => response,
		Err(failure) => failure.render(Dialect::Anthropic),
	}
}

async fn answer(state: &AppState, body: &Value) -> Result<Response, Failure> {
	let messages =
		body["messages"].as_array().ok_or_else(|| Failure::invalid("messages is required"))?;
	let conversation =
		message::parse_anthropic(&body["system"], messages).map_err(Failure::invalid)?;
	let model = http::resolve_model(&state.bridge, body["model"].as_str())?;
	let id = format!("msg_{}", http::random_id());
	let request = turn::Request {
		conversation,
		model: model.clone(),
		effort: effort(body),
		schema: schema(body),
		reply_id: id.clone(),
		previous: None,
	};
	let mut updates = http::start(&state.bridge, request).await?;
	let head = Head { id, model, thinking: shows_thinking(body) };
	if body["stream"].as_bool().unwrap_or(false) {
		return Ok(streamed(Events::new(head), updates).into_response());
	}
	let mut collected = Vec::new();
	while let Some(update) = updates.recv().await {
		collected.push(update);
	}
	Ok(Json(assemble(&head, collected)?).into_response())
}

/// Anthropic returns reasoning only to a request that turned thinking on.
fn shows_thinking(body: &Value) -> bool {
	matches!(body["thinking"]["type"].as_str(), Some("enabled" | "adaptive"))
}

/// `output_config.effort` names a level directly; `max` is the CLI's `xhigh`. Without it, a
/// thinking budget is read as a level: the CLI takes levels, not token counts.
fn effort(body: &Value) -> Option<String> {
	if let Some(effort) = body["output_config"]["effort"].as_str() {
		return Some(if effort == "max" { "xhigh" } else { effort }.to_owned());
	}
	let budget = body["thinking"]["budget_tokens"].as_u64()?;
	Some(
		match budget {
			..4096 => "low",
			4096..16384 => "medium",
			_ => "high",
		}
		.to_owned(),
	)
}

/// Structured output, from `output_config.format` or the older `output_format`.
fn schema(body: &Value) -> Option<Value> {
	let format = match &body["output_config"]["format"] {
		Value::Null => &body["output_format"],
		format => format,
	};
	(format["type"].as_str() == Some("json_schema")).then(|| format["schema"].clone())
}

pub struct Head {
	pub id: String,
	pub model: String,
	pub thinking: bool,
}

/// The whole reply to a request that did not stream.
pub fn assemble(head: &Head, updates: Vec<Update>) -> Result<Value, Failure> {
	let (mut text, mut reasoning) = (String::new(), String::new());
	for update in updates {
		match update {
			Update::Content(chunk) => text.push_str(&chunk),
			Update::Reasoning(chunk) => reasoning.push_str(&chunk),
			Update::Done(Outcome { stop_reason, usage }) => {
				let mut content = Vec::new();
				if head.thinking && !reasoning.is_empty() {
					content.push(json!({ "type": "thinking", "thinking": reasoning, "signature": "" }));
				}
				content.push(json!({ "type": "text", "text": text }));
				return Ok(json!({
					"id": head.id,
					"type": "message",
					"role": "assistant",
					"model": head.model,
					"content": content,
					"stop_reason": stop_reason_of(&stop_reason),
					"stop_sequence": null,
					"usage": usage_body(usage),
				}));
			}
			Update::Failed(message) => return Err(Failure::upstream(message)),
		}
	}
	Err(Failure::upstream("the turn ended without an answer"))
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Block {
	Thinking,
	Text,
}

/// Renders a turn's updates as Anthropic's stream events. The stream is stateful where OpenAI's is
/// not: content arrives in numbered blocks, each opened and closed, so a switch from reasoning to
/// text closes one block and opens the next.
pub struct Events {
	head: Head,
	open: Option<Block>,
	index: usize,
}

type Named = (&'static str, Value);

impl Events {
	pub fn new(head: Head) -> Self {
		Self { head, open: None, index: 0 }
	}

	/// `message_start`, with usage still zero: the agent reports it only at the end, and
	/// `message_delta` carries it then.
	pub fn opening(&self) -> Named {
		let message = json!({
			"id": self.head.id,
			"type": "message",
			"role": "assistant",
			"model": self.head.model,
			"content": [],
			"stop_reason": null,
			"stop_sequence": null,
			"usage": { "input_tokens": 0, "output_tokens": 0 },
		});
		("message_start", json!({ "type": "message_start", "message": message }))
	}

	/// The events one update becomes, and whether the stream ends with them.
	pub fn render(&mut self, update: Update) -> (Vec<Named>, bool) {
		match update {
			Update::Reasoning(_) if !self.head.thinking => (Vec::new(), false),
			Update::Reasoning(chunk) => {
				let mut events = self.switch_to(Block::Thinking);
				events.push(self.delta(json!({ "type": "thinking_delta", "thinking": chunk })));
				(events, false)
			}
			Update::Content(chunk) => {
				let mut events = self.switch_to(Block::Text);
				events.push(self.delta(json!({ "type": "text_delta", "text": chunk })));
				(events, false)
			}
			Update::Done(Outcome { stop_reason, usage }) => {
				// A reply always has a text block, as a whole one does, even if it is empty.
				let mut events = if self.open.is_none() { self.switch_to(Block::Text) } else { Vec::new() };
				events.extend(self.close());
				events.push((
					"message_delta",
					json!({
						"type": "message_delta",
						"delta": { "stop_reason": stop_reason_of(&stop_reason), "stop_sequence": null },
						"usage": usage_body(usage),
					}),
				));
				events.push(("message_stop", json!({ "type": "message_stop" })));
				(events, true)
			}
			Update::Failed(message) => {
				(vec![("error", error_body(FailureKind::Upstream, &message))], true)
			}
		}
	}

	fn switch_to(&mut self, block: Block) -> Vec<Named> {
		if self.open == Some(block) {
			return Vec::new();
		}
		let mut events = self.close();
		let content_block = match block {
			Block::Thinking => json!({ "type": "thinking", "thinking": "", "signature": "" }),
			Block::Text => json!({ "type": "text", "text": "" }),
		};
		events.push((
			"content_block_start",
			json!({ "type": "content_block_start", "index": self.index, "content_block": content_block }),
		));
		self.open = Some(block);
		events
	}

	fn close(&mut self) -> Vec<Named> {
		if self.open.take().is_none() {
			return Vec::new();
		}
		let event = json!({ "type": "content_block_stop", "index": self.index });
		self.index += 1;
		vec![("content_block_stop", event)]
	}

	fn delta(&self, delta: Value) -> Named {
		(
			"content_block_delta",
			json!({ "type": "content_block_delta", "index": self.index, "delta": delta }),
		)
	}
}

fn streamed(mut events: Events, mut updates: mpsc::Receiver<Update>) -> impl IntoResponse {
	let (tx, rx) = mpsc::channel::<Result<Event, Infallible>>(64);
	tokio::spawn(async move {
		let send = |(name, value): Named| {
			let tx = tx.clone();
			async move { tx.send(Ok(Event::default().event(name).data(value.to_string()))).await.is_ok() }
		};
		if !send(events.opening()).await {
			return;
		}
		while let Some(update) = updates.recv().await {
			let (named, done) = events.render(update);
			for event in named {
				if !send(event).await {
					return;
				}
			}
			if done {
				return;
			}
		}
	});
	http::event_stream(rx)
}

fn stop_reason_of(stop_reason: &str) -> &'static str {
	match stop_reason {
		"max_tokens" => "max_tokens",
		"refusal" => "refusal",
		_ => "end_turn",
	}
}

/// Anthropic's `input_tokens` is the uncached part alone, where ACP's `inputTokens` is the whole
/// prompt; the cached parts are counted beside it.
fn usage_body(usage: Usage) -> Value {
	json!({
		"input_tokens": usage.input.saturating_sub(usage.cache_read + usage.cache_creation),
		"output_tokens": usage.output,
		"cache_read_input_tokens": usage.cache_read,
		"cache_creation_input_tokens": usage.cache_creation,
	})
}

pub fn error_body(kind: FailureKind, message: &str) -> Value {
	let kind = match kind {
		FailureKind::Invalid => "invalid_request_error",
		FailureKind::Unauthorized => "authentication_error",
		FailureKind::NotFound => "not_found_error",
		FailureKind::Upstream => "api_error",
	};
	json!({ "type": "error", "error": { "type": kind, "message": message } })
}

pub fn model_object(model: &Model) -> Value {
	json!({
		"type": "model",
		"id": model.id,
		"display_name": model.name,
		"created_at": "1970-01-01T00:00:00Z",
	})
}

pub fn model_list(models: &[Model]) -> Value {
	json!({
		"data": models.iter().map(model_object).collect::<Vec<_>>(),
		"has_more": false,
		"first_id": models.first().map(|model| model.id.as_str()),
		"last_id": models.last().map(|model| model.id.as_str()),
	})
}

#[cfg(test)]
mod tests {
	use super::*;

	fn head(thinking: bool) -> Head {
		Head { id: "msg_1".into(), model: "grok-4.7".into(), thinking }
	}

	fn done() -> Update {
		let usage = Usage { input: 100, output: 10, cache_read: 40, cache_creation: 0, reasoning: 4 };
		Update::Done(Outcome { stop_reason: "end_turn".into(), usage })
	}

	fn names(events: &[Named]) -> Vec<&str> {
		events.iter().map(|(name, _)| *name).collect()
	}

	#[test]
	fn thinking_is_returned_only_when_asked_for() {
		let updates = || vec![Update::Reasoning("hm".into()), Update::Content("Hi".into()), done()];
		let with = assemble(&head(true), updates()).unwrap();
		assert_eq!(with["content"][0]["type"], "thinking");
		assert_eq!(with["content"][1]["text"], "Hi");
		let without = assemble(&head(false), updates()).unwrap();
		assert_eq!(without["content"].as_array().unwrap().len(), 1);
		assert_eq!(without["content"][0]["type"], "text");
	}

	#[test]
	fn input_tokens_are_the_uncached_part() {
		let reply = assemble(&head(false), vec![Update::Content("Hi".into()), done()]).unwrap();
		assert_eq!(reply["usage"]["input_tokens"], 60);
		assert_eq!(reply["usage"]["cache_read_input_tokens"], 40);
		assert_eq!(reply["stop_reason"], "end_turn");
	}

	#[test]
	fn the_stream_opens_and_closes_blocks_in_order() {
		let mut events = Events::new(head(true));
		assert_eq!(events.opening().0, "message_start");
		let mut all = Vec::new();
		for update in [
			Update::Reasoning("a".into()),
			Update::Reasoning("b".into()),
			Update::Content("Hi".into()),
			done(),
		] {
			all.extend(events.render(update).0);
		}
		assert_eq!(
			names(&all),
			[
				"content_block_start",
				"content_block_delta",
				"content_block_delta",
				"content_block_stop",
				"content_block_start",
				"content_block_delta",
				"content_block_stop",
				"message_delta",
				"message_stop",
			]
		);
		assert_eq!(all[0].1["content_block"]["type"], "thinking");
		assert_eq!(all[4].1["index"], 1);
		assert_eq!(all[4].1["content_block"]["type"], "text");
		assert_eq!(all[7].1["delta"]["stop_reason"], "end_turn");
	}

	#[test]
	fn hidden_thinking_leaves_one_text_block() {
		let mut events = Events::new(head(false));
		let mut all = Vec::new();
		for update in [Update::Reasoning("a".into()), Update::Content("Hi".into()), done()] {
			all.extend(events.render(update).0);
		}
		assert_eq!(all[0].1["content_block"]["type"], "text");
		assert_eq!(all[0].1["index"], 0);
	}

	#[test]
	fn an_empty_reply_still_has_a_text_block() {
		let mut events = Events::new(head(false));
		let (all, finished) = events.render(done());
		assert!(finished);
		assert_eq!(
			names(&all),
			["content_block_start", "content_block_stop", "message_delta", "message_stop"]
		);
	}

	#[test]
	fn efforts() {
		assert_eq!(effort(&json!({ "output_config": { "effort": "max" } })).as_deref(), Some("xhigh"));
		assert_eq!(
			effort(&json!({ "thinking": { "type": "enabled", "budget_tokens": 1024 } })).as_deref(),
			Some("low")
		);
		assert_eq!(
			effort(&json!({ "thinking": { "type": "enabled", "budget_tokens": 8000 } })).as_deref(),
			Some("medium")
		);
		assert_eq!(
			effort(&json!({ "thinking": { "type": "enabled", "budget_tokens": 32000 } })).as_deref(),
			Some("high")
		);
		assert_eq!(effort(&json!({})), None);
	}

	#[test]
	fn schemas() {
		let schema = json!({ "type": "object" });
		assert_eq!(
			super::schema(&json!({ "output_format": { "type": "json_schema", "schema": schema } })),
			Some(schema.clone())
		);
		assert_eq!(
			super::schema(
				&json!({ "output_config": { "format": { "type": "json_schema", "schema": schema } } })
			),
			Some(schema)
		);
		assert_eq!(super::schema(&json!({})), None);
	}

	#[test]
	fn errors_have_anthropics_shape() {
		let body = error_body(FailureKind::Unauthorized, "no");
		assert_eq!(body["type"], "error");
		assert_eq!(body["error"]["type"], "authentication_error");
	}
}
