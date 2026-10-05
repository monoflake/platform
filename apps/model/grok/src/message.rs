//! A chat completions request's messages, split into what a session is keyed on and what is sent.
//! See spec/architecture/grok/sessions.md for why the history is the key, and
//! spec/architecture/grok/api.md for what is accepted.

use std::hash::{DefaultHasher, Hash, Hasher};

use base64::Engine;
use serde_json::{Value, json};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Role {
	User,
	Assistant,
}

#[derive(Clone, Debug)]
pub enum Part {
	Text(String),
	/// Base64 image data as a data URL carried it, with its media type.
	Image {
		mime: String,
		data: String,
	},
}

#[derive(Clone, Debug)]
pub struct Message {
	pub role: Role,
	pub parts: Vec<Part>,
}

/// What a message is compared by when a request is matched to a session. Text is trimmed,
/// because clients differ on the whitespace they keep around a reply they echo back; an image is
/// its digest, so a session holding a day of history does not hold every image in it.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MessageKey {
	role: Role,
	text: String,
	images: Vec<u64>,
}

impl Message {
	pub fn key(&self) -> MessageKey {
		let mut images = Vec::new();
		for part in &self.parts {
			if let Part::Image { data, .. } = part {
				let mut hasher = DefaultHasher::new();
				data.hash(&mut hasher);
				images.push(hasher.finish());
			}
		}
		MessageKey { role: self.role, text: self.text().trim().to_owned(), images }
	}

	/// The message's text parts, joined.
	pub fn text(&self) -> String {
		let texts: Vec<&str> = self
			.parts
			.iter()
			.filter_map(|part| match part {
				Part::Text(text) => Some(text.as_str()),
				Part::Image { .. } => None,
			})
			.collect();
		texts.join("\n")
	}

	pub fn assistant(text: String) -> Self {
		Self { role: Role::Assistant, parts: vec![Part::Text(text)] }
	}
}

impl Part {
	/// The part as an ACP content block.
	pub fn block(&self) -> Value {
		match self {
			Part::Text(text) => json!({ "type": "text", "text": text }),
			Part::Image { mime, data } => json!({ "type": "image", "mimeType": mime, "data": data }),
		}
	}
}

/// A request's messages: the system text, the turns before the last, and the last, which is
/// always the user's.
pub struct Conversation {
	pub system: String,
	pub history: Vec<Message>,
	pub last: Message,
}

impl Conversation {
	pub fn history_keys(&self) -> Vec<MessageKey> {
		self.history.iter().map(Message::key).collect()
	}
}

/// Reads an OpenAI `messages` array. An error is the message a 400 carries.
pub fn parse_openai(messages: &[Value]) -> Result<Conversation, String> {
	let mut system = Vec::new();
	let mut turns = Vec::new();
	for (index, message) in messages.iter().enumerate() {
		let role = message["role"].as_str().unwrap_or_default();
		let parts =
			parse_content(&message["content"]).map_err(|error| format!("messages[{index}]: {error}"))?;
		match role {
			// A system message anywhere is part of the system prompt, which a session is created
			// with; `developer` is the newer name for the same thing.
			"system" | "developer" => system.push(Message { role: Role::User, parts }.text()),
			"user" => turns.push(Message { role: Role::User, parts }),
			"assistant" => turns.push(Message { role: Role::Assistant, parts }),
			"tool" | "function" => {
				return Err(format!("messages[{index}]: function calling is not supported"));
			}
			other => return Err(format!("messages[{index}]: unknown role {other:?}")),
		}
	}
	conversation(system.join("\n\n"), turns)
}

/// Reads an Anthropic request's `system` and `messages`. The result is the same `Conversation`
/// an OpenAI request makes, so a conversation continues its session whichever shape it arrives in.
pub fn parse_anthropic(system: &Value, messages: &[Value]) -> Result<Conversation, String> {
	let system = match system {
		Value::Null => String::new(),
		Value::String(text) => text.clone(),
		Value::Array(blocks) => {
			blocks.iter().filter_map(|block| block["text"].as_str()).collect::<Vec<_>>().join("\n\n")
		}
		_ => return Err("system must be a string or an array of text blocks".into()),
	};
	let mut turns = Vec::new();
	for (index, message) in messages.iter().enumerate() {
		let role = match message["role"].as_str() {
			Some("user") => Role::User,
			Some("assistant") => Role::Assistant,
			other => return Err(format!("messages[{index}]: unknown role {other:?}")),
		};
		let parts = match &message["content"] {
			Value::String(text) => vec![Part::Text(text.clone())],
			Value::Array(blocks) => {
				let mut parts = Vec::new();
				for block in blocks {
					if let Some(part) =
						parse_anthropic_block(block).map_err(|error| format!("messages[{index}]: {error}"))?
					{
						parts.push(part);
					}
				}
				parts
			}
			_ => {
				return Err(format!("messages[{index}]: content must be a string or an array of blocks"));
			}
		};
		turns.push(Message { role, parts });
	}
	conversation(system, turns)
}

/// A content block, or nothing for one that is only ever an echo of an earlier answer.
fn parse_anthropic_block(block: &Value) -> Result<Option<Part>, String> {
	match block["type"].as_str() {
		Some("text") => Ok(Some(Part::Text(block["text"].as_str().unwrap_or_default().to_owned()))),
		Some("image") => {
			let source = &block["source"];
			if source["type"].as_str() != Some("base64") {
				return Err("only base64 image sources are accepted".into());
			}
			let mime = source["media_type"].as_str().ok_or("the image has no media_type")?;
			let data = source["data"].as_str().ok_or("the image has no data")?;
			image(mime, data).map(Some)
		}
		// A client sends the reasoning of an earlier answer back with it; the session that wrote
		// it already has it, and it is no part of what a conversation is matched on.
		Some("thinking" | "redacted_thinking") => Ok(None),
		Some("tool_use" | "tool_result" | "server_tool_use" | "web_search_tool_result") => {
			Err("function calling is not supported".into())
		}
		Some(other) => Err(format!("content block type {other:?} is not supported")),
		None => Err("content block has no type".into()),
	}
}

/// Reads a Responses request's `instructions` and `input`. `input` is a string, one user message,
/// or a list of items, of which messages are read and echoed reasoning is passed over.
pub fn parse_responses(instructions: &Value, input: &Value) -> Result<Conversation, String> {
	let mut system: Vec<String> = instructions.as_str().map(str::to_owned).into_iter().collect();
	let items = match input {
		Value::String(text) => return conversation(join(system), vec![user_text(text)]),
		Value::Array(items) => items,
		_ => return Err("input must be a string or an array of items".into()),
	};
	let mut turns = Vec::new();
	for (index, item) in items.iter().enumerate() {
		let located = |error: String| format!("input[{index}]: {error}");
		match item["type"].as_str() {
			Some("message") | None => {}
			Some("reasoning") => continue,
			Some(kind) if kind.ends_with("_call") || kind.ends_with("_call_output") => {
				return Err(located("function calling is not supported".into()));
			}
			Some(other) => return Err(located(format!("item type {other:?} is not supported"))),
		}
		let parts = match &item["content"] {
			Value::String(text) => vec![Part::Text(text.clone())],
			Value::Array(parts) => {
				parts.iter().map(parse_responses_part).collect::<Result<_, _>>().map_err(located)?
			}
			_ => return Err(located("content must be a string or an array of parts".into())),
		};
		match item["role"].as_str() {
			Some("system" | "developer") => system.push(Message { role: Role::User, parts }.text()),
			Some("user") => turns.push(Message { role: Role::User, parts }),
			Some("assistant") => turns.push(Message { role: Role::Assistant, parts }),
			other => return Err(located(format!("unknown role {other:?}"))),
		}
	}
	conversation(join(system), turns)
}

fn parse_responses_part(part: &Value) -> Result<Part, String> {
	match part["type"].as_str() {
		Some("input_text" | "output_text") => {
			Ok(Part::Text(part["text"].as_str().unwrap_or_default().to_owned()))
		}
		Some("refusal") => Ok(Part::Text(part["refusal"].as_str().unwrap_or_default().to_owned())),
		Some("input_image") => match part["image_url"].as_str() {
			Some(url) => parse_data_url(url),
			None => Err("only images given as data: URLs are accepted".into()),
		},
		Some(other) => Err(format!("content part type {other:?} is not supported")),
		None => Err("content part has no type".into()),
	}
}

fn user_text(text: &str) -> Message {
	Message { role: Role::User, parts: vec![Part::Text(text.to_owned())] }
}

fn join(system: Vec<String>) -> String {
	system.join("\n\n")
}

fn conversation(system: String, mut turns: Vec<Message>) -> Result<Conversation, String> {
	let last = turns.pop().ok_or("messages has no user or assistant message")?;
	if last.role != Role::User {
		return Err("the last message must be the user's".into());
	}
	Ok(Conversation { system, history: turns, last })
}

fn parse_content(content: &Value) -> Result<Vec<Part>, String> {
	match content {
		Value::Null => Ok(Vec::new()),
		Value::String(text) => Ok(vec![Part::Text(text.clone())]),
		Value::Array(parts) => parts.iter().map(parse_part).collect(),
		_ => Err("content must be a string or an array of parts".into()),
	}
}

fn parse_part(part: &Value) -> Result<Part, String> {
	match part["type"].as_str() {
		Some("text") => Ok(Part::Text(part["text"].as_str().unwrap_or_default().to_owned())),
		Some("image_url") => {
			let url = part["image_url"]["url"].as_str().or_else(|| part["image_url"].as_str());
			parse_data_url(url.ok_or("image_url has no url")?)
		}
		Some(other) => Err(format!("content part type {other:?} is not supported")),
		None => Err("content part has no type".into()),
	}
}

/// Only a `data:` URL is accepted; grok2api fetches nothing on a caller's behalf
/// (spec/architecture/grok/api.md).
fn parse_data_url(url: &str) -> Result<Part, String> {
	let rest = url.strip_prefix("data:").ok_or("only data: URLs are accepted for images")?;
	let (header, data) = rest.split_once(',').ok_or("the data URL has no data")?;
	let mime = header.strip_suffix(";base64").ok_or("the data URL must be base64")?;
	image(mime, data)
}

fn image(mime: &str, data: &str) -> Result<Part, String> {
	if !mime.starts_with("image/") {
		return Err(format!("{mime} is not an image type"));
	}
	base64::engine::general_purpose::STANDARD
		.decode(data)
		.map_err(|_| "the image is not valid base64".to_owned())?;
	Ok(Part::Image { mime: mime.to_owned(), data: data.to_owned() })
}

#[cfg(test)]
mod tests {
	use serde_json::json;

	use super::*;

	#[test]
	fn splits_system_history_and_last() {
		let conversation = parse_openai(&[
			json!({ "role": "system", "content": "Be brief." }),
			json!({ "role": "user", "content": "Hi" }),
			json!({ "role": "assistant", "content": "Hello." }),
			json!({ "role": "user", "content": [{ "type": "text", "text": "Again" }] }),
		])
		.unwrap();
		assert_eq!(conversation.system, "Be brief.");
		assert_eq!(conversation.history.len(), 2);
		assert_eq!(conversation.last.text(), "Again");
	}

	#[test]
	fn keys_ignore_surrounding_whitespace() {
		let echoed = Message::assistant("Hello.\n".into());
		assert_eq!(echoed.key(), Message::assistant("Hello.".into()).key());
	}

	#[test]
	fn refuses_a_remote_image() {
		let part = json!({ "type": "image_url", "image_url": { "url": "https://example.com/a.png" } });
		assert!(parse_part(&part).is_err());
	}

	#[test]
	fn accepts_a_data_url_image() {
		let part =
			json!({ "type": "image_url", "image_url": { "url": "data:image/png;base64,iVBORw0K" } });
		assert!(matches!(parse_part(&part), Ok(Part::Image { .. })));
	}

	#[test]
	fn the_last_message_is_the_users() {
		assert!(parse_openai(&[json!({ "role": "assistant", "content": "Hi" })]).is_err());
	}

	#[test]
	fn an_anthropic_request_matches_the_openai_one() {
		let anthropic = parse_anthropic(
			&json!([{ "type": "text", "text": "Be brief." }]),
			&[
				json!({ "role": "user", "content": "Hi" }),
				json!({ "role": "assistant", "content": [
					{ "type": "thinking", "thinking": "...", "signature": "" },
					{ "type": "text", "text": "Hello." },
				] }),
				json!({ "role": "user", "content": "Again" }),
			],
		)
		.unwrap();
		let openai = parse_openai(&[
			json!({ "role": "system", "content": "Be brief." }),
			json!({ "role": "user", "content": "Hi" }),
			json!({ "role": "assistant", "content": "Hello." }),
			json!({ "role": "user", "content": "Again" }),
		])
		.unwrap();
		assert_eq!(anthropic.system, openai.system);
		assert_eq!(anthropic.history_keys(), openai.history_keys());
	}

	#[test]
	fn an_anthropic_image_must_be_inline() {
		let url =
			json!({ "type": "image", "source": { "type": "url", "url": "https://example.com/a.png" } });
		assert!(parse_anthropic_block(&url).is_err());
		let inline = json!({ "type": "image", "source": { "type": "base64", "media_type": "image/png", "data": "iVBORw0K" } });
		assert!(matches!(parse_anthropic_block(&inline), Ok(Some(Part::Image { .. }))));
	}

	#[test]
	fn anthropic_tool_blocks_are_refused() {
		let block = json!({ "type": "tool_result", "tool_use_id": "x", "content": "42" });
		assert!(parse_anthropic_block(&block).is_err());
	}

	#[test]
	fn a_responses_request_matches_the_openai_one() {
		let responses = parse_responses(
			&json!("Be brief."),
			&json!([
				{ "role": "user", "content": "Hi" },
				{ "type": "reasoning", "id": "rs_1", "summary": [] },
				{ "type": "message", "role": "assistant", "content": [{ "type": "output_text", "text": "Hello." }] },
				{ "role": "user", "content": [{ "type": "input_text", "text": "Again" }] },
			]),
		)
		.unwrap();
		let openai = parse_openai(&[
			json!({ "role": "system", "content": "Be brief." }),
			json!({ "role": "user", "content": "Hi" }),
			json!({ "role": "assistant", "content": "Hello." }),
			json!({ "role": "user", "content": "Again" }),
		])
		.unwrap();
		assert_eq!(responses.system, openai.system);
		assert_eq!(responses.history_keys(), openai.history_keys());
		assert_eq!(responses.last.text(), "Again");
	}

	#[test]
	fn a_responses_string_is_one_user_message() {
		let conversation = parse_responses(&Value::Null, &json!("Hi")).unwrap();
		assert!(conversation.history.is_empty());
		assert_eq!(conversation.last.text(), "Hi");
	}

	#[test]
	fn responses_tool_items_are_refused() {
		let input = json!([{ "type": "function_call_output", "call_id": "1", "output": "42" }]);
		assert!(parse_responses(&Value::Null, &input).is_err());
		let image =
			json!([{ "role": "user", "content": [{ "type": "input_image", "file_id": "file_1" }] }]);
		assert!(parse_responses(&Value::Null, &image).is_err());
	}
}
