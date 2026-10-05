//! A stand-in for `grok agent stdio`: enough of ACP for grok2api to run against, with every answer
//! saying what the agent saw, so the tests can check what grok2api sent without spending anything.
//!
//! An answer reads `session=<id> turn=<n> model=<m> effort=<e> images=<n> schema=<bool>
//! said=<text>`. A prompt containing `SLOW` streams for seconds and honors cancellation, one
//! containing `TOOL` asks permission for a tool first, and `STATS` answers with what the agent has
//! counted.

use std::collections::{HashMap, HashSet};
use std::io::{BufRead, Write};
use std::sync::mpsc::{Sender, channel};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde_json::{Value, json};

const MODELS: [&str; 2] = ["fake-1", "fake-2"];
const EFFORTS: [&str; 3] = ["low", "medium", "high"];

#[derive(Default)]
struct Session {
	turn: u64,
	model: String,
	effort: String,
}

#[derive(Default)]
struct State {
	sessions: HashMap<String, Session>,
	cancelled: HashSet<String>,
	cancels: u64,
	closes: u64,
	/// Prompts that asked for X data.
	fetches: u64,
	/// Replies the client owes to requests this agent sent, by id.
	waiting: HashMap<u64, Sender<Value>>,
}

type Shared = Arc<Mutex<State>>;
type Out = Arc<Mutex<std::io::Stdout>>;

fn send(out: &Out, message: Value) {
	let mut out = out.lock().unwrap();
	writeln!(out, "{message}").unwrap();
	out.flush().unwrap();
}

fn update(out: &Out, session: &str, update: Value) {
	send(
		out,
		json!({ "jsonrpc": "2.0", "method": "session/update", "params": { "sessionId": session, "update": update } }),
	);
}

fn chunk(kind: &str, text: &str) -> Value {
	json!({ "sessionUpdate": kind, "content": { "type": "text", "text": text } })
}

pub fn run() {
	let state: Shared = Arc::default();
	let out: Out = Arc::new(Mutex::new(std::io::stdout()));
	let mut next_session = 0;
	for line in std::io::stdin().lock().lines() {
		let Ok(line) = line else { break };
		let message: Value = serde_json::from_str(&line).unwrap();
		let id = message["id"].clone();
		let params = &message["params"];
		let reply = |result: Value| json!({ "jsonrpc": "2.0", "id": id, "result": result });
		let refuse = |text: &str| json!({ "jsonrpc": "2.0", "id": id, "error": { "code": -32602, "message": "Invalid params", "data": text } });
		match message["method"].as_str() {
			None => {
				let waiting = state.lock().unwrap().waiting.remove(&id.as_u64().unwrap());
				if let Some(tx) = waiting {
					let _ = tx.send(message["result"].clone());
				}
			}
			Some("initialize") => send(
				&out,
				reply(json!({ "_meta": {
					"agentVersion": "0.0.1",
					"defaultAuthMethodId": "cached_token",
					"modelState": { "currentModelId": "fake-1", "availableModels": [
						{ "modelId": "fake-1", "name": "Fake One" },
						{ "modelId": "fake-2", "name": "Fake Two" },
					] },
				} })),
			),
			Some("session/new") => {
				next_session += 1;
				let session = format!("fake-{next_session}");
				let profiled =
					params["_meta"]["agentProfile"].as_str().is_some_and(|name| name.starts_with("grok2api"));
				let tools = if profiled { 698 } else { 8831 };
				eprintln!(
					"INFO session.context_snapshot: session_context_snapshot: emitted model=\"fake-1\" skills_tokens=0 system_prompt_tokens=2 tool_definitions_tokens={tools} mcp_tokens=0 agents_md_tokens=0 workflows_tokens=0 skills_count=0"
				);
				let fresh = Session { model: "fake-1".into(), effort: "high".into(), ..Default::default() };
				state.lock().unwrap().sessions.insert(session.clone(), fresh);
				send(&out, reply(json!({ "sessionId": session })));
			}
			Some("session/set_config_option") => {
				let (config, value) =
					(params["configId"].as_str().unwrap(), params["value"].as_str().unwrap());
				let valid = match config {
					"model" => MODELS.contains(&value),
					"reasoning_effort" => EFFORTS.contains(&value),
					_ => false,
				};
				if !valid {
					send(&out, refuse("unknown value"));
					continue;
				}
				let mut state = state.lock().unwrap();
				let session = state.sessions.get_mut(params["sessionId"].as_str().unwrap()).unwrap();
				match config {
					"model" => session.model = value.into(),
					_ => session.effort = value.into(),
				}
				send(&out, reply(json!({})));
			}
			Some("session/prompt") => {
				let (state, out, params) = (state.clone(), out.clone(), params.clone());
				std::thread::spawn(move || prompt(&state, &out, id, &params));
			}
			Some("session/cancel") => {
				let mut state = state.lock().unwrap();
				state.cancels += 1;
				state.cancelled.insert(params["sessionId"].as_str().unwrap().into());
			}
			Some("session/close") => {
				state.lock().unwrap().closes += 1;
				send(&out, reply(json!({})));
			}
			Some(_) => send(
				&out,
				json!({ "jsonrpc": "2.0", "id": id, "error": { "code": -32601, "message": "unknown" } }),
			),
		}
	}
}

fn prompt(state: &Shared, out: &Out, id: Value, params: &Value) {
	let session = params["sessionId"].as_str().unwrap().to_owned();
	let blocks = params["prompt"].as_array().unwrap();
	let said: Vec<&str> = blocks.iter().filter_map(|block| block["text"].as_str()).collect();
	let said = said.join(" ");
	let images = blocks.iter().filter(|block| block["type"] == "image").count();
	let schema = params["_meta"].get("outputSchema").is_some();
	let done = |stop: &str| {
		let meta = json!({ "inputTokens": 100, "outputTokens": 10, "cachedReadTokens": 40, "reasoningTokens": 4 });
		send(
			out,
			json!({ "jsonrpc": "2.0", "id": id, "result": { "stopReason": stop, "_meta": meta } }),
		);
	};

	if let Some(properties) = params["_meta"]["outputSchema"]["properties"].as_object()
		&& ["found", "posts", "users"].iter().any(|key| properties.contains_key(*key))
	{
		state.lock().unwrap().fetches += 1;
		return x_answer(state, out, &session, &said, properties, done);
	}
	if said.contains("STATS") {
		let text = {
			let state = state.lock().unwrap();
			format!("cancels={} closes={} fetches={}", state.cancels, state.closes, state.fetches)
		};
		update(out, &session, chunk("agent_message_chunk", &text));
		return done("end_turn");
	}
	if said.contains("SLOW") {
		for _ in 0..100 {
			if state.lock().unwrap().cancelled.remove(&session) {
				return done("cancelled");
			}
			update(out, &session, chunk("agent_message_chunk", "."));
			std::thread::sleep(Duration::from_millis(50));
		}
		return done("end_turn");
	}
	let mut permission = String::new();
	if said.contains("TOOL") {
		let (tx, rx) = channel();
		state.lock().unwrap().waiting.insert(900, tx);
		send(
			out,
			json!({ "jsonrpc": "2.0", "id": 900, "method": "session/request_permission", "params": {
			"sessionId": session,
			"toolCall": { "title": "rm -rf /" },
			"options": [{ "optionId": "allow", "kind": "allow_once" }, { "optionId": "deny", "kind": "reject_once" }],
		} }),
		);
		let outcome = rx.recv_timeout(Duration::from_secs(5)).unwrap_or_default();
		permission =
			format!(" permission={}", outcome["outcome"]["optionId"].as_str().unwrap_or("none"));
	}

	let text = {
		let mut state = state.lock().unwrap();
		let entry = state.sessions.get_mut(&session).unwrap();
		entry.turn += 1;
		format!(
			"session={session} turn={} model={} effort={} images={images} schema={schema}{permission} said={said}",
			entry.turn, entry.model, entry.effort
		)
	};
	update(out, &session, chunk("agent_thought_chunk", "thinking"));
	let middle = (0..=text.len() / 2).rev().find(|&index| text.is_char_boundary(index)).unwrap();
	let (head, tail) = text.split_at(middle);
	update(out, &session, chunk("agent_message_chunk", head));
	update(out, &session, chunk("agent_message_chunk", tail));
	done("end_turn");
}

/// The tool arguments a grok2api X prompt carries: the JSON after "arguments: ".
fn arguments(said: &str) -> Value {
	let start = said.find("arguments: ").map(|at| at + "arguments: ".len()).unwrap();
	let mut stream = serde_json::Deserializer::from_str(&said[start..]).into_iter::<Value>();
	stream.next().unwrap().unwrap()
}

/// A post as the model would write it. Ids ending in 7 were posted just now, the rest in 2025; ids
/// ending in 4 quote the post before them.
fn fake_post(id: u128) -> Value {
	let created_at = if id % 10 == 7 { utc_now() } else { "2025-09-25T14:34:15Z".to_owned() };
	json!({
		"id": id.to_string(),
		"text": format!("post {id}"),
		"created_at": created_at,
		"conversation_id": id.to_string(),
		"author": { "username": "fake_user", "name": "Fake", "avatar_url": format!("{}/profile_images/1/a.jpg", monoflake::EXTERNAL_X_MEDIA) },
		"metrics": { "likes": 1, "reposts": 0, "quotes": 0, "replies": 0, "bookmarks": 0, "views": 10 },
		"media": [{ "type": "photo", "url": format!("{}/media/fake.jpg", monoflake::EXTERNAL_X_MEDIA) }],
		"quoted": if id % 10 == 4 { fake_quoted(id - 1) } else { Value::Null },
	})
}

fn fake_quoted(id: u128) -> Value {
	let mut post = fake_post(id);
	post.as_object_mut().unwrap().remove("quoted");
	post
}

fn utc_now() -> String {
	let output =
		std::process::Command::new("date").args(["-u", "+%Y-%m-%dT%H:%M:%SZ"]).output().unwrap();
	String::from_utf8(output.stdout).unwrap().trim().to_owned()
}

fn x_answer(
	state: &Shared,
	out: &Out,
	session: &str,
	said: &str,
	properties: &serde_json::Map<String, Value>,
	done: impl Fn(&str),
) {
	let arguments = arguments(said);
	let answer = if properties.contains_key("posts") {
		let query = arguments["query"].as_str().unwrap_or_default();
		let limit = arguments["limit"].as_u64().unwrap_or(3) as u128;
		let top = query
			.split(' ')
			.find_map(|term| term.strip_prefix("max_id:"))
			.map(|max| max.parse::<u128>().unwrap())
			.unwrap_or(1000);
		let count = if query.contains("SHORT") { limit.min(3) } else { limit };
		let mut posts: Vec<Value> = (0..count).map(|offset| fake_post(top - offset)).collect();
		if query.contains("DIRTY") {
			posts[0]["id"] = "not-an-id".into();
		}
		if arguments.get("usernames").is_some() {
			posts[0]["text"] = format!("args={arguments}").into();
		}
		json!({ "posts": posts })
	} else if properties.contains_key("users") {
		let count = arguments["count"].as_u64().unwrap_or(3);
		let users: Vec<Value> = (0..count)
			.map(|index| json!({ "id": format!("{}", 100 + index), "username": format!("user{index}"), "name": "User", "avatar_url": null, "bio": "bio", "followers": 5, "verified": null }))
			.collect();
		json!({ "users": users })
	} else if properties.contains_key("user") {
		let name = arguments["query"].as_str().unwrap();
		if name == "nobody" {
			json!({ "found": false, "user": null })
		} else {
			json!({ "found": true, "user": { "id": "42", "username": name.to_uppercase(), "name": "Found", "avatar_url": null, "bio": null, "followers": 7, "verified": "Blue Verified" } })
		}
	} else {
		let id: u128 = arguments["post_id"].as_str().unwrap().parse().unwrap();
		if id == 404 {
			json!({ "found": false, "post": null, "parents": [], "replies": [] })
		} else if properties.contains_key("parents") {
			json!({ "found": true, "post": fake_post(id), "parents": [fake_post(id - 1)], "replies": [fake_post(id + 1), fake_post(id + 2)] })
		} else {
			json!({ "found": true, "post": fake_post(id) })
		}
	};
	let text = answer.to_string();
	if said.contains("SLOWLIST") {
		// Written a few characters at a time, so a short budget ends it partway.
		for piece in text.as_bytes().chunks(40) {
			if state.lock().unwrap().cancelled.remove(session) {
				return done("cancelled");
			}
			update(out, session, chunk("agent_message_chunk", std::str::from_utf8(piece).unwrap()));
			std::thread::sleep(Duration::from_millis(60));
		}
	} else {
		update(out, session, chunk("agent_message_chunk", &text));
	}
	done("end_turn");
}
