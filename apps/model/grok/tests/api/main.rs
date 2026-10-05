//! grok2api end to end against a fake agent: the real server, the real HTTP, no subscription spent.
//!
//! This binary is both halves. Started as `<it> agent stdio` it is the fake agent (see fake.rs);
//! started by `cargo test` it runs grok2api with `GROK2API_GROK_BIN` pointing back at itself.

mod fake;
mod twitter;

use std::net::TcpListener;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

use serde_json::{Value, json};

const KEY: &str = "test-key";

fn main() {
	let args: Vec<String> = std::env::args().skip(1).collect();
	match args.iter().map(String::as_str).collect::<Vec<_>>().as_slice() {
		["agent", "stdio"] => fake::run(),
		["--version"] => println!("grok 0.0.1 (fake)"),
		// cargo passes the harness's own flags; this harness has none to honor.
		_ => tokio::runtime::Runtime::new().unwrap().block_on(run_all()),
	}
}

pub struct Server {
	child: Child,
	base: String,
	client: reqwest::Client,
	_data: TempDir,
}

impl Drop for Server {
	fn drop(&mut self) {
		let _ = self.child.kill();
	}
}

struct TempDir(std::path::PathBuf);

impl Drop for TempDir {
	fn drop(&mut self) {
		let _ = std::fs::remove_dir_all(&self.0);
	}
}

async fn start(settings: &[(&str, &str)]) -> Server {
	let port = TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
	let data = std::env::temp_dir().join(format!("grok2api-test-{}-{port}", std::process::id()));
	let child = Command::new(env!("CARGO_BIN_EXE_grok2api"))
		.env("GROK2API_API_KEY", KEY)
		.env("GROK2API_PORT", port.to_string())
		.env("GROK2API_DATA_DIR", &data)
		.env("GROK2API_GROK_BIN", std::env::current_exe().unwrap())
		.env("RUST_LOG", "warn")
		.envs(settings.iter().copied())
		.stdout(Stdio::null())
		.spawn()
		.unwrap();
	let server = Server {
		child,
		base: format!("http://{}", std::net::SocketAddr::from(([127, 0, 0, 1], port))),
		client: reqwest::Client::new(),
		_data: TempDir(data),
	};
	for _ in 0..100 {
		if server.client.get(format!("{}/v1/models", server.base)).send().await.is_ok() {
			return server;
		}
		tokio::time::sleep(Duration::from_millis(100)).await;
	}
	panic!("grok2api did not start");
}

impl Server {
	async fn post(&self, path: &str, body: Value, headers: &[(&str, &str)]) -> (u16, String) {
		let mut request = self.client.post(format!("{}{path}", self.base)).json(&body);
		for (name, value) in headers {
			request = request.header(*name, *value);
		}
		let response = request.send().await.unwrap();
		(response.status().as_u16(), response.text().await.unwrap())
	}

	pub async fn get(&self, path: &str, headers: &[(&str, &str)]) -> (u16, Value) {
		let mut request = self.client.get(format!("{}{path}", self.base));
		for (name, value) in headers {
			request = request.header(*name, *value);
		}
		let response = request.send().await.unwrap();
		(response.status().as_u16(), response.json().await.unwrap())
	}

	/// A non-streamed chat completion: status and body.
	pub async fn chat(&self, body: Value) -> (u16, Value) {
		let (status, text) =
			self.post("/v1/chat/completions", body, &[("authorization", BEARER)]).await;
		(status, serde_json::from_str(&text).unwrap())
	}

	async fn responses(&self, body: Value) -> (u16, Value) {
		let (status, text) = self.post("/v1/responses", body, &[("authorization", BEARER)]).await;
		(status, serde_json::from_str(&text).unwrap())
	}

	async fn messages(&self, body: Value) -> (u16, Value) {
		let (status, text) = self.post("/v1/messages", body, &[("x-api-key", KEY)]).await;
		(status, serde_json::from_str(&text).unwrap())
	}
}

pub const BEARER: &str = "Bearer test-key";

pub fn content(reply: &Value) -> &str {
	reply["choices"][0]["message"]["content"].as_str().unwrap()
}

/// The `key=value` a fake answer reports.
pub fn field<'a>(answer: &'a str, key: &str) -> &'a str {
	let start = answer.find(&format!("{key}=")).unwrap_or_else(|| panic!("no {key} in {answer}"))
		+ key.len()
		+ 1;
	answer[start..].split(' ').next().unwrap()
}

pub fn user(text: &str) -> Value {
	json!({ "role": "user", "content": text })
}

fn assistant(text: &str) -> Value {
	json!({ "role": "assistant", "content": text })
}

/// `(event, data)` pairs from a server-sent event body.
fn events(body: &str) -> Vec<(String, String)> {
	let mut parsed = Vec::new();
	let mut name = String::new();
	for line in body.lines() {
		if let Some(value) = line.strip_prefix("event: ") {
			name = value.to_owned();
		} else if let Some(value) = line.strip_prefix("data: ") {
			parsed.push((std::mem::take(&mut name), value.to_owned()));
		}
	}
	parsed
}

async fn run_all() {
	let server = start(&[]).await;
	macro_rules! run {
		($($case:ident),* $(,)?) => {$(
			$case(&server).await;
			println!("test {} ... ok", stringify!($case));
		)*};
	}
	run!(
		answers_health_without_a_key,
		refuses_a_missing_key,
		lists_models_in_both_shapes,
		answers_a_chat_completion,
		continues_a_session_and_seeds_an_edited_one,
		switches_model_and_effort_on_a_session,
		refuses_what_cannot_be_answered,
		passes_images_and_schemas,
		streams_openai_chunks,
		answers_anthropic_messages,
		streams_anthropic_events,
		continues_across_shapes,
		refuses_tools_the_agent_asks_for,
		cancels_when_the_client_leaves,
		answers_responses,
		streams_responses_events,
		continues_by_previous_response_id,
	);
	twitter::run_all(&server).await;
	drop(server);
	let waiting =
		start(&[("GROK2API_TWITTER_FAST_RESPONSE", "false"), ("GROK2API_TWITTER_TIMEOUT_SECS", "2")])
			.await;
	twitter::run_waiting(&waiting).await;
}

async fn answers_health_without_a_key(server: &Server) {
	let (status, body) = server.get("/health", &[]).await;
	assert_eq!(status, 200);
	assert_eq!(body["status"], "success");
}

async fn refuses_a_missing_key(server: &Server) {
	let (status, body) = server.get("/v1/models", &[]).await;
	assert_eq!(status, 401);
	assert_eq!(body["error"]["code"], "invalid_api_key");
	let (status, text) = server.post("/v1/messages", json!({}), &[("x-api-key", "wrong")]).await;
	assert_eq!(status, 401);
	assert_eq!(
		serde_json::from_str::<Value>(&text).unwrap()["error"]["type"],
		"authentication_error"
	);
}

async fn lists_models_in_both_shapes(server: &Server) {
	let (_, openai) = server.get("/v1/models", &[("authorization", BEARER)]).await;
	assert_eq!(openai["object"], "list");
	assert_eq!(openai["data"][1]["id"], "fake-2");
	let anthropic_headers = [("x-api-key", KEY), ("anthropic-version", "2023-06-01")];
	let (_, anthropic) = server.get("/v1/models", &anthropic_headers).await;
	assert_eq!(anthropic["data"][0]["display_name"], "Fake One");
	assert_eq!(anthropic["last_id"], "fake-2");
	let (status, one) = server.get("/v1/models/fake-2", &[("authorization", BEARER)]).await;
	assert_eq!((status, one["id"].as_str()), (200, Some("fake-2")));
	let (status, _) = server.get("/v1/models/nope", &[("authorization", BEARER)]).await;
	assert_eq!(status, 404);
}

async fn answers_a_chat_completion(server: &Server) {
	let (status, reply) =
		server.chat(json!({ "messages": [user("hello")], "temperature": 0.1, "max_tokens": 5 })).await;
	assert_eq!(status, 200);
	assert_eq!(field(content(&reply), "said"), "hello");
	assert_eq!(field(content(&reply), "model"), "fake-1", "no model means the default");
	assert_eq!(reply["choices"][0]["message"]["reasoning_content"], "thinking");
	assert_eq!(reply["choices"][0]["finish_reason"], "stop");
	assert_eq!(reply["usage"]["total_tokens"], 110);
	assert_eq!(reply["usage"]["prompt_tokens_details"]["cached_tokens"], 40);
}

async fn continues_a_session_and_seeds_an_edited_one(server: &Server) {
	let (_, first) = server.chat(json!({ "model": "fake-1", "messages": [user("one")] })).await;
	let answer = content(&first).to_owned();
	let session = field(&answer, "session").to_owned();
	let history = json!([user("one"), assistant(&answer), user("two")]);
	let (_, second) = server.chat(json!({ "model": "fake-1", "messages": history })).await;
	assert_eq!(field(content(&second), "session"), session, "an extended conversation continues");
	assert_eq!(field(content(&second), "turn"), "2");
	assert_eq!(field(content(&second), "said"), "two", "only the new message is sent");

	let edited = json!([user("one"), assistant("an answer nobody gave"), user("two")]);
	let (_, third) = server.chat(json!({ "model": "fake-1", "messages": edited })).await;
	let answer = content(&third);
	assert_ne!(field(answer, "session"), session, "an edited conversation starts over");
	assert!(answer.contains("<turn role=\"assistant\">"), "and is seeded with its history: {answer}");
}

async fn switches_model_and_effort_on_a_session(server: &Server) {
	let (_, first) = server.chat(json!({ "model": "fake-1", "messages": [user("a")] })).await;
	let answer = content(&first).to_owned();
	let history = json!([user("a"), assistant(&answer), user("b")]);
	let body = json!({ "model": "fake-2", "reasoning_effort": "low", "messages": history });
	let (_, second) = server.chat(body).await;
	assert_eq!(field(content(&second), "session"), field(&answer, "session"));
	assert_eq!(field(content(&second), "model"), "fake-2");
	assert_eq!(field(content(&second), "effort"), "low");
	let (status, third) =
		server.chat(json!({ "reasoning_effort": "ultra", "messages": [user("c")] })).await;
	assert_eq!(status, 200, "an effort the model lacks is ignored");
	assert_eq!(field(content(&third), "effort"), "high");
}

async fn refuses_what_cannot_be_answered(server: &Server) {
	for (body, status) in [
		(json!({ "n": 2, "messages": [user("x")] }), 400),
		(json!({ "model": "gpt-4o", "messages": [user("x")] }), 404),
		(json!({ "messages": [assistant("x")] }), 400),
		(
			json!({ "messages": [user("x"), { "role": "tool", "content": "42", "tool_call_id": "1" }] }),
			400,
		),
		(
			json!({ "messages": [{ "role": "user", "content": [{ "type": "image_url", "image_url": { "url": "https://example.com/a.png" } }] }] }),
			400,
		),
		(json!({}), 400),
	] {
		let (got, reply) = server.chat(body.clone()).await;
		assert_eq!(got, status, "{body} gave {reply}");
		assert!(reply["error"]["message"].is_string());
	}
	let image =
		json!({ "type": "image", "source": { "type": "url", "url": "https://example.com/a.png" } });
	let (status, reply) =
		server.messages(json!({ "messages": [{ "role": "user", "content": [image] }] })).await;
	assert_eq!(status, 400);
	assert_eq!(reply["error"]["type"], "invalid_request_error");
}

async fn passes_images_and_schemas(server: &Server) {
	let image =
		json!({ "type": "image_url", "image_url": { "url": "data:image/png;base64,iVBORw0KGgo=" } });
	let message =
		json!({ "role": "user", "content": [{ "type": "text", "text": "what is it" }, image] });
	let format = json!({ "type": "json_schema", "json_schema": { "name": "x", "schema": { "type": "object" } } });
	let (_, reply) = server.chat(json!({ "messages": [message], "response_format": format })).await;
	assert_eq!(field(content(&reply), "images"), "1");
	assert_eq!(field(content(&reply), "schema"), "true");
	let block = json!({ "type": "image", "source": { "type": "base64", "media_type": "image/png", "data": "iVBORw0KGgo=" } });
	let (_, reply) =
		server.messages(json!({ "messages": [{ "role": "user", "content": [block] }] })).await;
	assert_eq!(field(reply["content"][0]["text"].as_str().unwrap(), "images"), "1");
}

async fn streams_openai_chunks(server: &Server) {
	let body = json!({ "stream": true, "stream_options": { "include_usage": true }, "messages": [user("streamed")] });
	let (status, text) =
		server.post("/v1/chat/completions", body, &[("authorization", BEARER)]).await;
	assert_eq!(status, 200);
	let data: Vec<String> = events(&text).into_iter().map(|(_, data)| data).collect();
	assert_eq!(data.last().unwrap(), "[DONE]");
	let chunks: Vec<Value> =
		data[..data.len() - 1].iter().map(|data| serde_json::from_str(data).unwrap()).collect();
	assert_eq!(chunks[0]["choices"][0]["delta"]["role"], "assistant");
	let delta = |key: &str| -> String {
		chunks.iter().filter_map(|chunk| chunk["choices"][0]["delta"][key].as_str()).collect()
	};
	assert_eq!(delta("reasoning_content"), "thinking");
	assert_eq!(field(&delta("content"), "said"), "streamed");
	let finish =
		chunks.iter().find(|chunk| chunk["choices"][0]["finish_reason"].is_string()).unwrap();
	assert_eq!(finish["choices"][0]["finish_reason"], "stop");
	assert_eq!(chunks.last().unwrap()["usage"]["completion_tokens"], 10);
}

async fn answers_anthropic_messages(server: &Server) {
	let body =
		json!({ "model": "fake-1", "max_tokens": 100, "system": "be brief", "messages": [user("hi")] });
	let (status, reply) = server.messages(body.clone()).await;
	assert_eq!(status, 200);
	assert_eq!(reply["type"], "message");
	assert_eq!(reply["content"].as_array().unwrap().len(), 1, "no thinking unless asked");
	assert_eq!(field(reply["content"][0]["text"].as_str().unwrap(), "said"), "hi");
	assert_eq!(reply["stop_reason"], "end_turn");
	assert_eq!(reply["usage"]["input_tokens"], 60);
	assert_eq!(reply["usage"]["cache_read_input_tokens"], 40);

	let mut thinking = body;
	thinking["thinking"] = json!({ "type": "enabled", "budget_tokens": 2048 });
	let (_, reply) = server.messages(thinking).await;
	assert_eq!(reply["content"][0]["type"], "thinking");
	assert_eq!(field(reply["content"][1]["text"].as_str().unwrap(), "effort"), "low");
}

async fn streams_anthropic_events(server: &Server) {
	let body = json!({ "stream": true, "max_tokens": 100, "thinking": { "type": "enabled", "budget_tokens": 20000 }, "messages": [user("s")] });
	let (status, text) = server.post("/v1/messages", body, &[("x-api-key", KEY)]).await;
	assert_eq!(status, 200);
	let events = events(&text);
	let names: Vec<&str> = events.iter().map(|(name, _)| name.as_str()).collect();
	assert_eq!(names.first(), Some(&"message_start"));
	assert_eq!(names.last(), Some(&"message_stop"));
	let starts: Vec<Value> = events
		.iter()
		.filter(|(name, _)| name == "content_block_start")
		.map(|(_, data)| serde_json::from_str(data).unwrap())
		.collect();
	assert_eq!(starts.len(), 2);
	assert_eq!(starts[0]["content_block"]["type"], "thinking");
	assert_eq!(starts[1]["content_block"]["type"], "text");
	assert_eq!(starts[1]["index"], 1);
	let delta: Value =
		serde_json::from_str(&events.iter().find(|(name, _)| name == "message_delta").unwrap().1)
			.unwrap();
	assert_eq!(delta["usage"]["output_tokens"], 10);
}

async fn continues_across_shapes(server: &Server) {
	let (_, first) = server.chat(json!({ "messages": [user("shape")] })).await;
	let answer = content(&first).to_owned();
	let body =
		json!({ "max_tokens": 10, "messages": [user("shape"), assistant(&answer), user("next")] });
	let (_, second) = server.messages(body).await;
	let text = second["content"][0]["text"].as_str().unwrap();
	assert_eq!(field(text, "session"), field(&answer, "session"));
	assert_eq!(field(text, "turn"), "2");
}

async fn refuses_tools_the_agent_asks_for(server: &Server) {
	let (_, reply) = server.chat(json!({ "messages": [user("TOOL please")] })).await;
	assert_eq!(field(content(&reply), "permission"), "deny");
}

async fn cancels_when_the_client_leaves(server: &Server) {
	let body = json!({ "stream": true, "messages": [user("SLOW")] });
	let response = server
		.client
		.post(format!("{}/v1/chat/completions", server.base))
		.header("authorization", BEARER)
		.json(&body)
		.send()
		.await
		.unwrap();
	let mut response = response;
	response.chunk().await.unwrap();
	drop(response);
	for _ in 0..50 {
		tokio::time::sleep(Duration::from_millis(100)).await;
		let (_, stats) = server.chat(json!({ "messages": [user("STATS")] })).await;
		let stats = content(&stats).to_owned();
		if field(&stats, "cancels") != "0" && field(&stats, "closes") != "0" {
			return;
		}
	}
	panic!("the agent was never told to cancel");
}

/// The text of a Responses answer's message item.
fn output_text(response: &Value) -> String {
	let message =
		response["output"].as_array().unwrap().iter().find(|item| item["type"] == "message").unwrap();
	message["content"][0]["text"].as_str().unwrap().to_owned()
}

async fn answers_responses(server: &Server) {
	let (status, response) =
		server.responses(json!({ "input": "hello", "instructions": "be brief" })).await;
	assert_eq!(status, 200);
	assert_eq!(response["object"], "response");
	assert_eq!(response["status"], "completed");
	assert!(response["id"].as_str().unwrap().starts_with("resp_"));
	assert_eq!(
		response["output"].as_array().unwrap().len(),
		1,
		"no reasoning unless a summary is asked for"
	);
	assert_eq!(field(&output_text(&response), "said"), "hello");
	assert_eq!(response["usage"]["input_tokens_details"]["cached_tokens"], 40);

	let body = json!({
		"reasoning": { "effort": "minimal", "summary": "auto" },
		"text": { "format": { "type": "json_schema", "name": "x", "schema": { "type": "object" } } },
		"input": [{ "role": "user", "content": [
			{ "type": "input_text", "text": "look" },
			{ "type": "input_image", "image_url": "data:image/png;base64,iVBORw0KGgo=" },
		] }],
	});
	let (_, response) = server.responses(body).await;
	assert_eq!(response["output"][0]["type"], "reasoning");
	let text = output_text(&response);
	assert_eq!(
		(field(&text, "effort"), field(&text, "images"), field(&text, "schema")),
		("low", "1", "true")
	);

	let (status, reply) = server
		.responses(
			json!({ "input": [{ "type": "function_call_output", "call_id": "1", "output": "42" }] }),
		)
		.await;
	assert_eq!(status, 400);
	assert!(reply["error"]["message"].is_string());
}

async fn streams_responses_events(server: &Server) {
	let body = json!({ "stream": true, "reasoning": { "summary": "auto" }, "input": "s" });
	let (status, text) = server.post("/v1/responses", body, &[("authorization", BEARER)]).await;
	assert_eq!(status, 200);
	let events = events(&text);
	let names: Vec<&str> = events.iter().map(|(name, _)| name.as_str()).collect();
	assert_eq!(names.first(), Some(&"response.created"));
	assert_eq!(names.last(), Some(&"response.completed"));
	assert_eq!(names.iter().filter(|name| **name == "response.output_item.added").count(), 2);
	let numbers: Vec<u64> = events
		.iter()
		.map(|(_, data)| {
			serde_json::from_str::<Value>(data).unwrap()["sequence_number"].as_u64().unwrap()
		})
		.collect();
	assert_eq!(numbers, (0..numbers.len() as u64).collect::<Vec<_>>());
	let completed: Value = serde_json::from_str(&events.last().unwrap().1).unwrap();
	assert_eq!(field(&output_text(&completed["response"]), "said"), "s");
}

async fn continues_by_previous_response_id(server: &Server) {
	let (_, first) = server.responses(json!({ "input": "first" })).await;
	let session = field(&output_text(&first), "session").to_owned();
	let (_, second) =
		server.responses(json!({ "previous_response_id": first["id"], "input": "second" })).await;
	let text = output_text(&second);
	assert_eq!(field(&text, "session"), session);
	assert_eq!((field(&text, "turn"), field(&text, "said")), ("2", "second"));
	assert_eq!(second["previous_response_id"], first["id"]);

	let resent = json!([
		{ "role": "user", "content": "first" },
		{ "role": "assistant", "content": [{ "type": "output_text", "text": output_text(&first) }] },
		{ "role": "user", "content": "second" },
		{ "role": "assistant", "content": [{ "type": "output_text", "text": text }] },
		{ "role": "user", "content": "third" },
	]);
	let (_, third) = server.responses(json!({ "input": resent })).await;
	assert_eq!(
		field(&output_text(&third), "session"),
		session,
		"a resent conversation continues too"
	);
	assert_eq!(field(&output_text(&third), "turn"), "3");

	let (status, reply) =
		server.responses(json!({ "previous_response_id": "resp_nope", "input": "x" })).await;
	assert_eq!(status, 400);
	assert!(reply["error"]["message"].as_str().unwrap().contains("resp_nope"));
}
