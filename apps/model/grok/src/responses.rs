//! OpenAI's Responses shape; spec/architecture/grok/api.md.

use std::convert::Infallible;

use axum::Json;
use axum::extract::State;
use axum::response::sse::Event;
use axum::response::{IntoResponse, Response};
use serde_json::{Value, json};
use tokio::sync::mpsc;

use crate::http::{self, AppState, Dialect, Failure};
use crate::message;
use crate::turn::{self, Outcome, Update, Usage};

pub async fn responses(State(state): State<AppState>, Json(body): Json<Value>) -> Response {
	match answer(&state, &body).await {
		Ok(response) => response,
		Err(failure) => failure.render(Dialect::OpenAi),
	}
}

async fn answer(state: &AppState, body: &Value) -> Result<Response, Failure> {
	let conversation =
		message::parse_responses(&body["instructions"], &body["input"]).map_err(Failure::invalid)?;
	let model = http::resolve_model(&state.bridge, body["model"].as_str())?;
	let id = format!("resp_{}", http::random_id());
	let previous = body["previous_response_id"].as_str().map(str::to_owned);
	let request = turn::Request {
		conversation,
		model: model.clone(),
		effort: effort(&body["reasoning"]),
		schema: schema(&body["text"]["format"]),
		reply_id: id.clone(),
		previous: previous.clone(),
	};
	let mut updates = http::start(&state.bridge, request).await?;
	let head = Head {
		id,
		created_at: http::now(),
		model,
		previous,
		instructions: body["instructions"].clone(),
		reasoning: body["reasoning"].clone(),
		format: body["text"]["format"].clone(),
	};
	if body["stream"].as_bool().unwrap_or(false) {
		return Ok(streamed(Events::new(head), updates).into_response());
	}
	let mut collected = Vec::new();
	while let Some(update) = updates.recv().await {
		collected.push(update);
	}
	Ok(Json(assemble(&head, collected)?).into_response())
}

/// OpenAI's levels run from `none` to `xhigh`; the CLI's from `low`. The two below its floor are
/// read as its floor.
fn effort(reasoning: &Value) -> Option<String> {
	let effort = reasoning["effort"].as_str()?;
	Some(if matches!(effort, "none" | "minimal") { "low" } else { effort }.to_owned())
}

/// `text.format` as the schema the agent takes; the format carries its schema inline.
fn schema(format: &Value) -> Option<Value> {
	match format["type"].as_str() {
		Some("json_schema") => format.get("schema").cloned(),
		Some("json_object") => Some(json!({ "type": "object" })),
		_ => None,
	}
}

/// What a response object repeats back from its request.
pub struct Head {
	pub id: String,
	pub created_at: u64,
	pub model: String,
	pub previous: Option<String>,
	pub instructions: Value,
	pub reasoning: Value,
	pub format: Value,
}

impl Head {
	/// Reasoning comes back as a summary only when one was asked for, as OpenAI returns it.
	fn summarizes(&self) -> bool {
		self.reasoning["summary"].as_str().is_some_and(|summary| summary != "none")
	}

	fn object(&self, status: &str, output: Vec<Value>, usage: Option<Usage>) -> Value {
		json!({
			"id": self.id,
			"object": "response",
			"created_at": self.created_at,
			"status": status,
			"model": self.model,
			"output": output,
			"usage": usage.map(usage_body),
			"error": null,
			"incomplete_details": null,
			"instructions": self.instructions,
			"previous_response_id": self.previous,
			"reasoning": { "effort": self.reasoning["effort"], "summary": self.reasoning["summary"] },
			"text": { "format": if self.format.is_null() { json!({ "type": "text" }) } else { self.format.clone() } },
			"tools": [],
			"tool_choice": "auto",
			"parallel_tool_calls": true,
			"store": false,
			"metadata": {},
		})
	}

	/// The finished response: `incomplete` when the agent ran out of output, as OpenAI marks it.
	fn finished(&self, stop_reason: &str, output: Vec<Value>, usage: Usage) -> Value {
		if stop_reason == "max_tokens" {
			let mut object = self.object("incomplete", output, Some(usage));
			object["incomplete_details"] = json!({ "reason": "max_output_tokens" });
			return object;
		}
		self.object("completed", output, Some(usage))
	}
}

fn reasoning_item(id: &str, text: &str) -> Value {
	json!({ "type": "reasoning", "id": id, "summary": [{ "type": "summary_text", "text": text }] })
}

fn message_item(id: &str, status: &str, text: &str) -> Value {
	json!({
		"type": "message",
		"id": id,
		"status": status,
		"role": "assistant",
		"content": [{ "type": "output_text", "text": text, "annotations": [] }],
	})
}

fn item_id(prefix: &str) -> String {
	format!("{prefix}_{}", http::random_id())
}

/// The whole response to a request that did not stream.
pub fn assemble(head: &Head, updates: Vec<Update>) -> Result<Value, Failure> {
	let (mut text, mut reasoning) = (String::new(), String::new());
	for update in updates {
		match update {
			Update::Content(chunk) => text.push_str(&chunk),
			Update::Reasoning(chunk) => reasoning.push_str(&chunk),
			Update::Done(Outcome { stop_reason, usage }) => {
				let mut output = Vec::new();
				if head.summarizes() && !reasoning.is_empty() {
					output.push(reasoning_item(&item_id("rs"), &reasoning));
				}
				output.push(message_item(&item_id("msg"), "completed", &text));
				return Ok(head.finished(&stop_reason, output, usage));
			}
			Update::Failed(message) => return Err(Failure::upstream(message)),
		}
	}
	Err(Failure::upstream("the turn ended without an answer"))
}

#[derive(Clone, Copy, Debug, PartialEq)]
enum Kind {
	Reasoning,
	Message,
}

struct Item {
	kind: Kind,
	id: String,
	index: usize,
	text: String,
}

/// Renders a turn's updates as Responses stream events. Like Anthropic's, the stream is stateful:
/// output arrives in items, each added, filled and finished, and every event is numbered.
pub struct Events {
	head: Head,
	sequence: u64,
	current: Option<Item>,
	finished: Vec<Value>,
}

type Named = (String, Value);

impl Events {
	pub fn new(head: Head) -> Self {
		Self { head, sequence: 0, current: None, finished: Vec::new() }
	}

	fn event(&mut self, kind: &str, mut body: Value) -> Named {
		body["type"] = kind.into();
		body["sequence_number"] = self.sequence.into();
		self.sequence += 1;
		(kind.to_owned(), body)
	}

	pub fn opening(&mut self) -> Vec<Named> {
		let response = self.head.object("in_progress", Vec::new(), None);
		vec![
			self.event("response.created", json!({ "response": response })),
			self.event("response.in_progress", json!({ "response": response })),
		]
	}

	/// The events one update becomes, and whether the stream ends with them.
	pub fn render(&mut self, update: Update) -> (Vec<Named>, bool) {
		match update {
			Update::Reasoning(_) if !self.head.summarizes() => (Vec::new(), false),
			Update::Reasoning(chunk) => {
				let mut events = self.switch_to(Kind::Reasoning);
				let (id, index) = self.append(&chunk);
				let body =
					json!({ "item_id": id, "output_index": index, "summary_index": 0, "delta": chunk });
				events.push(self.event("response.reasoning_summary_text.delta", body));
				(events, false)
			}
			Update::Content(chunk) => {
				let mut events = self.switch_to(Kind::Message);
				let (id, index) = self.append(&chunk);
				let body =
					json!({ "item_id": id, "output_index": index, "content_index": 0, "delta": chunk });
				events.push(self.event("response.output_text.delta", body));
				(events, false)
			}
			Update::Done(Outcome { stop_reason, usage }) => {
				// A response always has a message, as a whole one does, even if it is empty.
				let mut events = if self.finished.iter().any(|item| item["type"] == "message")
					|| self.current.as_ref().is_some_and(|item| item.kind == Kind::Message)
				{
					Vec::new()
				} else {
					self.switch_to(Kind::Message)
				};
				events.extend(self.close());
				let response = self.head.finished(&stop_reason, self.finished.clone(), usage);
				let kind = if response["status"] == "incomplete" {
					"response.incomplete"
				} else {
					"response.completed"
				};
				events.push(self.event(kind, json!({ "response": response })));
				(events, true)
			}
			Update::Failed(message) => {
				let mut response = self.head.object("failed", self.finished.clone(), None);
				response["error"] = json!({ "code": "server_error", "message": message });
				(vec![self.event("response.failed", json!({ "response": response }))], true)
			}
		}
	}

	fn append(&mut self, chunk: &str) -> (String, usize) {
		let item = self.current.as_mut().expect("an item is open");
		item.text.push_str(chunk);
		(item.id.clone(), item.index)
	}

	fn switch_to(&mut self, kind: Kind) -> Vec<Named> {
		if self.current.as_ref().is_some_and(|item| item.kind == kind) {
			return Vec::new();
		}
		let mut events = self.close();
		let index = self.finished.len();
		let (id, item, part_event, part) = match kind {
			Kind::Reasoning => {
				let id = item_id("rs");
				let item = json!({ "type": "reasoning", "id": id, "summary": [] });
				let part = json!({ "item_id": id, "output_index": index, "summary_index": 0, "part": { "type": "summary_text", "text": "" } });
				(id, item, "response.reasoning_summary_part.added", part)
			}
			Kind::Message => {
				let id = item_id("msg");
				let item = json!({ "type": "message", "id": id, "status": "in_progress", "role": "assistant", "content": [] });
				let part = json!({ "item_id": id, "output_index": index, "content_index": 0, "part": { "type": "output_text", "text": "", "annotations": [] } });
				(id, item, "response.content_part.added", part)
			}
		};
		events.push(
			self.event("response.output_item.added", json!({ "output_index": index, "item": item })),
		);
		events.push(self.event(part_event, part));
		self.current = Some(Item { kind, id, index, text: String::new() });
		events
	}

	fn close(&mut self) -> Vec<Named> {
		let Some(item) = self.current.take() else { return Vec::new() };
		let (id, index, text) = (&item.id, item.index, &item.text);
		let (done, part_done, whole) = match item.kind {
			Kind::Reasoning => (
				self.event("response.reasoning_summary_text.done", json!({ "item_id": id, "output_index": index, "summary_index": 0, "text": text })),
				self.event("response.reasoning_summary_part.done", json!({ "item_id": id, "output_index": index, "summary_index": 0, "part": { "type": "summary_text", "text": text } })),
				reasoning_item(id, text),
			),
			Kind::Message => (
				self.event("response.output_text.done", json!({ "item_id": id, "output_index": index, "content_index": 0, "text": text })),
				self.event("response.content_part.done", json!({ "item_id": id, "output_index": index, "content_index": 0, "part": { "type": "output_text", "text": text, "annotations": [] } })),
				message_item(id, "completed", text),
			),
		};
		let item_done =
			self.event("response.output_item.done", json!({ "output_index": index, "item": whole }));
		self.finished.push(whole);
		vec![done, part_done, item_done]
	}
}

fn streamed(mut events: Events, mut updates: mpsc::Receiver<Update>) -> impl IntoResponse {
	let (tx, rx) = mpsc::channel::<Result<Event, Infallible>>(64);
	tokio::spawn(async move {
		let send = |(name, value): Named| {
			let tx = tx.clone();
			async move { tx.send(Ok(Event::default().event(name).data(value.to_string()))).await.is_ok() }
		};
		for event in events.opening() {
			if !send(event).await {
				return;
			}
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

/// Responses counts `input_tokens` with the cached part inside it, as Chat Completions does.
fn usage_body(usage: Usage) -> Value {
	json!({
		"input_tokens": usage.input,
		"input_tokens_details": { "cached_tokens": usage.cache_read },
		"output_tokens": usage.output,
		"output_tokens_details": { "reasoning_tokens": usage.reasoning },
		"total_tokens": usage.input + usage.output,
	})
}

#[cfg(test)]
mod tests {
	use super::*;

	fn head(summary: Option<&str>) -> Head {
		Head {
			id: "resp_1".into(),
			created_at: 1,
			model: "grok-4.7".into(),
			previous: None,
			instructions: Value::Null,
			reasoning: json!({ "effort": "low", "summary": summary }),
			format: Value::Null,
		}
	}

	fn done(stop: &str) -> Update {
		let usage = Usage { input: 100, output: 10, cache_read: 40, cache_creation: 0, reasoning: 4 };
		Update::Done(Outcome { stop_reason: stop.into(), usage })
	}

	#[test]
	fn a_whole_response_has_a_message_and_asked_for_reasoning() {
		let updates =
			|| vec![Update::Reasoning("hm".into()), Update::Content("Hi".into()), done("end_turn")];
		let with = assemble(&head(Some("auto")), updates()).unwrap();
		assert_eq!(with["status"], "completed");
		assert_eq!(with["output"][0]["type"], "reasoning");
		assert_eq!(with["output"][0]["summary"][0]["text"], "hm");
		assert_eq!(with["output"][1]["content"][0]["text"], "Hi");
		assert_eq!(with["usage"]["input_tokens_details"]["cached_tokens"], 40);
		let without = assemble(&head(None), updates()).unwrap();
		assert_eq!(without["output"].as_array().unwrap().len(), 1);
	}

	#[test]
	fn running_out_of_output_is_incomplete() {
		let response =
			assemble(&head(None), vec![Update::Content("Hi".into()), done("max_tokens")]).unwrap();
		assert_eq!(response["status"], "incomplete");
		assert_eq!(response["incomplete_details"]["reason"], "max_output_tokens");
	}

	#[test]
	fn the_stream_adds_fills_and_finishes_items_in_order() {
		let mut events = Events::new(head(Some("auto")));
		let mut all = events.opening();
		for update in [
			Update::Reasoning("a".into()),
			Update::Content("H".into()),
			Update::Content("i".into()),
			done("end_turn"),
		] {
			all.extend(events.render(update).0);
		}
		let names: Vec<&str> = all.iter().map(|(name, _)| name.as_str()).collect();
		assert_eq!(
			names,
			[
				"response.created",
				"response.in_progress",
				"response.output_item.added",
				"response.reasoning_summary_part.added",
				"response.reasoning_summary_text.delta",
				"response.reasoning_summary_text.done",
				"response.reasoning_summary_part.done",
				"response.output_item.done",
				"response.output_item.added",
				"response.content_part.added",
				"response.output_text.delta",
				"response.output_text.delta",
				"response.output_text.done",
				"response.content_part.done",
				"response.output_item.done",
				"response.completed",
			]
		);
		let numbers: Vec<u64> =
			all.iter().map(|(_, body)| body["sequence_number"].as_u64().unwrap()).collect();
		assert_eq!(numbers, (0..numbers.len() as u64).collect::<Vec<_>>());
		assert_eq!(all[12].1["text"], "Hi");
		assert_eq!(all[8].1["output_index"], 1);
		let completed = &all.last().unwrap().1["response"];
		assert_eq!(completed["output"].as_array().unwrap().len(), 2);
		assert_eq!(completed["usage"]["output_tokens"], 10);
	}

	#[test]
	fn efforts_below_the_floor_are_the_floor() {
		assert_eq!(effort(&json!({ "effort": "minimal" })).as_deref(), Some("low"));
		assert_eq!(effort(&json!({ "effort": "xhigh" })).as_deref(), Some("xhigh"));
		assert_eq!(effort(&Value::Null), None);
	}

	#[test]
	fn formats() {
		let schema = json!({ "type": "object" });
		assert_eq!(
			super::schema(&json!({ "type": "json_schema", "name": "x", "schema": schema })),
			Some(schema)
		);
		assert_eq!(super::schema(&json!({ "type": "text" })), None);
	}
}
