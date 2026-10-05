//! The resident `grok agent stdio` process, spoken to over ACP: JSON-RPC 2.0, one message per
//! line. See spec/architecture/grok/bridge.md, "One resident agent, spoken to over ACP".

use std::collections::HashMap;
use std::path::Path;
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use anyhow::{Context, Result, anyhow};
use serde_json::{Value, json};
use tokio::io::{AsyncBufReadExt, AsyncWriteExt, BufReader};
use tokio::process::{Child, ChildStderr, ChildStdout};
use tokio::sync::{mpsc, oneshot};

use crate::environment::Environment;

/// An error the agent answered with, kept apart from transport failures so a caller can tell
/// "the agent said no" from "the agent is gone".
#[derive(Debug)]
pub struct RpcError {
	pub code: i64,
	pub message: String,
}

impl std::fmt::Display for RpcError {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		write!(f, "agent error {}: {}", self.code, self.message)
	}
}

impl std::error::Error for RpcError {}

type Pending = Arc<Mutex<HashMap<u64, oneshot::Sender<Result<Value, RpcError>>>>>;
type Subscribers = Arc<Mutex<HashMap<String, mpsc::UnboundedSender<Value>>>>;

/// What `initialize` told us about the agent.
pub struct AgentInfo {
	pub version: String,
	pub signed_in: bool,
	pub models: Vec<Model>,
	pub default_model: String,
}

#[derive(Debug)]
pub struct Model {
	pub id: String,
	/// What the CLI shows for it, `Grok 4.7` for `grok-4.7`.
	pub name: String,
}

impl AgentInfo {
	pub fn offers(&self, model: &str) -> bool {
		self.models.iter().any(|offered| offered.id == model)
	}
}

pub struct Agent {
	pub info: AgentInfo,
	writer: mpsc::UnboundedSender<String>,
	pending: Pending,
	subscribers: Subscribers,
	next_id: AtomicU64,
	/// Set once nothing holds the agent any more; its exit is then expected rather than fatal.
	retired: Arc<AtomicBool>,
	_child: Child,
}

/// An agent is dropped when it is replaced and its last session is gone, or when it failed the
/// check it was started for. Its child is killed with it, and that exit is not the server's.
impl Drop for Agent {
	fn drop(&mut self) {
		self.retired.store(true, Ordering::SeqCst);
	}
}

impl Agent {
	/// Starts an agent on `binary` and initializes it. The returned receiver carries its stderr
	/// lines, which is where the startup check reads the context breakdown from.
	pub async fn start(
		environment: &Environment,
		binary: &Path,
	) -> Result<(Arc<Self>, mpsc::UnboundedReceiver<String>)> {
		let mut child = environment
			.agent_command(binary)
			.stdin(Stdio::piped())
			.stdout(Stdio::piped())
			.stderr(Stdio::piped())
			.kill_on_drop(true)
			.spawn()
			.with_context(|| format!("cannot start {}", binary.display()))?;
		let stdin = child.stdin.take().context("agent has no stdin")?;
		let stdout = child.stdout.take().context("agent has no stdout")?;
		let stderr = child.stderr.take().context("agent has no stderr")?;

		let (writer, mut outbox) = mpsc::unbounded_channel::<String>();
		tokio::spawn(async move {
			let mut stdin = stdin;
			while let Some(line) = outbox.recv().await {
				if stdin.write_all(line.as_bytes()).await.is_err() || stdin.flush().await.is_err() {
					break;
				}
			}
		});

		let pending: Pending = Arc::default();
		let subscribers: Subscribers = Arc::default();
		let retired = Arc::new(AtomicBool::new(false));
		tokio::spawn(read_stdout(
			stdout,
			writer.clone(),
			pending.clone(),
			subscribers.clone(),
			retired.clone(),
		));
		let (log_tx, log_rx) = mpsc::unbounded_channel();
		tokio::spawn(read_stderr(stderr, log_tx));

		let info = match tokio::time::timeout(INITIALIZE_TIMEOUT, initialize(&writer, &pending)).await {
			Ok(Ok(info)) => info,
			// No Agent exists yet to be dropped, so the flag is set by hand before the child goes.
			Ok(Err(error)) => {
				retired.store(true, Ordering::SeqCst);
				return Err(error);
			}
			Err(_) => {
				retired.store(true, Ordering::SeqCst);
				anyhow::bail!(
					"{} did not answer initialize within {INITIALIZE_TIMEOUT:?}",
					binary.display()
				);
			}
		};
		let agent = Arc::new(Self {
			info,
			writer,
			pending,
			subscribers,
			next_id: AtomicU64::new(INITIALIZE_ID + 1),
			retired,
			_child: child,
		});
		Ok((agent, log_rx))
	}

	pub async fn request(&self, method: &str, params: Value) -> Result<Value> {
		let id = self.next_id.fetch_add(1, Ordering::Relaxed);
		call(&self.writer, &self.pending, id, method, params).await
	}

	pub fn notify(&self, method: &str, params: Value) -> Result<()> {
		self.send(json!({ "jsonrpc": "2.0", "method": method, "params": params }))
	}

	fn send(&self, message: Value) -> Result<()> {
		self.writer.send(format!("{message}\n")).map_err(|_| anyhow!("the agent's stdin is closed"))
	}

	/// Routes the session's `session/update` notifications to the returned receiver until
	/// `unsubscribe`. One subscriber per session: a session answers one prompt at a time.
	pub fn subscribe(&self, session_id: &str) -> mpsc::UnboundedReceiver<Value> {
		let (tx, rx) = mpsc::unbounded_channel();
		self.subscribers.lock().unwrap().insert(session_id.to_owned(), tx);
		rx
	}

	pub fn unsubscribe(&self, session_id: &str) {
		self.subscribers.lock().unwrap().remove(session_id);
	}

	/// A session in the clean workspace, on one of grok2api's profiles, with `system` replacing the
	/// agent's own system prompt outright.
	pub async fn new_session(
		&self,
		cwd: &std::path::Path,
		profile: crate::environment::Profile,
		system: &str,
	) -> Result<String> {
		let result = self
			.request(
				"session/new",
				json!({
					"cwd": cwd,
					"mcpServers": [],
					"_meta": {
						"systemPromptOverride": system,
						"agentProfile": profile.name(),
					},
				}),
			)
			.await?;
		result["sessionId"].as_str().map(str::to_owned).context("session/new returned no sessionId")
	}

	pub async fn set_option(&self, session_id: &str, config_id: &str, value: &str) -> Result<()> {
		self
			.request(
				"session/set_config_option",
				json!({ "sessionId": session_id, "configId": config_id, "value": value }),
			)
			.await
			.map(drop)
	}

	/// Sends one prompt and waits for its end; the streamed content arrives through `subscribe`.
	/// A schema constrains the answer to JSON matching it, the ACP side of the CLI's `--json-schema`.
	pub async fn prompt(
		&self,
		session_id: &str,
		blocks: Vec<Value>,
		schema: Option<&Value>,
	) -> Result<Value> {
		let mut params = json!({ "sessionId": session_id, "prompt": blocks });
		if let Some(schema) = schema {
			params["_meta"] = json!({ "outputSchema": schema });
		}
		self.request("session/prompt", params).await
	}

	pub fn cancel(&self, session_id: &str) {
		let _ = self.notify("session/cancel", json!({ "sessionId": session_id }));
	}

	pub async fn close(&self, session_id: &str) {
		if let Err(error) = self.request("session/close", json!({ "sessionId": session_id })).await {
			tracing::debug!(session_id, %error, "closing a session failed");
		}
	}
}

/// The id `initialize` is sent with; every later request counts up from it.
const INITIALIZE_ID: u64 = 1;

/// It answered in 0.1 s when measured; a binary that takes this long is not going to.
const INITIALIZE_TIMEOUT: std::time::Duration = std::time::Duration::from_secs(30);

async fn call(
	writer: &mpsc::UnboundedSender<String>,
	pending: &Pending,
	id: u64,
	method: &str,
	params: Value,
) -> Result<Value> {
	let (tx, rx) = oneshot::channel();
	pending.lock().unwrap().insert(id, tx);
	let message = json!({ "jsonrpc": "2.0", "id": id, "method": method, "params": params });
	writer.send(format!("{message}\n")).map_err(|_| anyhow!("the agent's stdin is closed"))?;
	match rx.await {
		Ok(Ok(result)) => Ok(result),
		Ok(Err(error)) => Err(error.into()),
		Err(_) => Err(anyhow!("the agent exited while {method} was pending")),
	}
}

async fn initialize(
	writer: &mpsc::UnboundedSender<String>,
	pending: &Pending,
) -> Result<AgentInfo> {
	let params = json!({
		"protocolVersion": 1,
		"clientCapabilities": { "fs": { "readTextFile": false, "writeTextFile": false }, "terminal": false },
	});
	let result = call(writer, pending, INITIALIZE_ID, "initialize", params).await?;
	let meta = &result["_meta"];
	let state = &meta["modelState"];
	let models: Vec<Model> = state["availableModels"]
		.as_array()
		.map(|models| {
			models
				.iter()
				.filter_map(|model| {
					let id = model["modelId"].as_str()?.to_owned();
					let name = model["name"].as_str().map(str::to_owned).unwrap_or_else(|| id.clone());
					Some(Model { id, name })
				})
				.collect()
		})
		.unwrap_or_default();
	Ok(AgentInfo {
		version: meta["agentVersion"].as_str().unwrap_or("unknown").to_owned(),
		signed_in: meta["defaultAuthMethodId"].as_str() == Some("cached_token"),
		default_model: state["currentModelId"]
			.as_str()
			.map(str::to_owned)
			.or_else(|| models.first().map(|model| model.id.clone()))
			.unwrap_or_default(),
		models,
	})
}

async fn read_stdout(
	stdout: ChildStdout,
	writer: mpsc::UnboundedSender<String>,
	pending: Pending,
	subscribers: Subscribers,
	retired: Arc<AtomicBool>,
) {
	let mut lines = BufReader::new(stdout).lines();
	while let Ok(Some(line)) = lines.next_line().await {
		let Ok(message) = serde_json::from_str::<Value>(&line) else {
			tracing::warn!(line, "the agent wrote a line that is not JSON");
			continue;
		};
		let id = message.get("id").and_then(Value::as_u64);
		match (message.get("method").and_then(Value::as_str), id) {
			(Some(method), Some(_)) => answer_request(&writer, method, &message),
			(Some("session/update"), None) => {
				let params = &message["params"];
				let Some(session_id) = params["sessionId"].as_str() else { continue };
				if let Some(tx) = subscribers.lock().unwrap().get(session_id) {
					let _ = tx.send(params["update"].clone());
				}
			}
			(Some(_), None) => {}
			(None, Some(id)) => {
				let Some(tx) = pending.lock().unwrap().remove(&id) else { continue };
				let outcome = match message.get("error") {
					Some(error) => Err(RpcError {
						code: error["code"].as_i64().unwrap_or(0),
						message: match error.get("data") {
							Some(Value::String(data)) => {
								format!("{}: {data}", error["message"].as_str().unwrap_or(""))
							}
							_ => error["message"].as_str().unwrap_or("").to_owned(),
						},
					}),
					None => Ok(message.get("result").cloned().unwrap_or(Value::Null)),
				};
				let _ = tx.send(outcome);
			}
			(None, None) => {}
		}
	}
	// Every pending request fails as its sender drops. A server whose agent is gone cannot answer
	// anything, so it stops and leaves the restart to whatever runs it;
	// spec/architecture/grok/bridge.md, "When the agent goes". An agent nothing holds any more was
	// killed on purpose.
	if retired.load(Ordering::SeqCst) {
		tracing::debug!("a retired agent exited");
		return;
	}
	tracing::error!("the agent exited");
	std::process::exit(1);
}

/// The agent asks the client for things only when it wants a tool to run. grok2api offers no
/// capabilities and approves nothing; spec/architecture/grok/bridge.md, "The model reaches for
/// tools".
fn answer_request(writer: &mpsc::UnboundedSender<String>, method: &str, message: &Value) {
	let id = &message["id"];
	let reply = if method == "session/request_permission" {
		let reject = message["params"]["options"].as_array().and_then(|options| {
			options
				.iter()
				.find(|option| option["kind"].as_str().is_some_and(|kind| kind.starts_with("reject")))
		});
		tracing::warn!(tool = %message["params"]["toolCall"]["title"], "refused a tool the agent asked to run");
		let outcome = match reject.and_then(|option| option["optionId"].as_str()) {
			Some(option_id) => json!({ "outcome": "selected", "optionId": option_id }),
			None => json!({ "outcome": "cancelled" }),
		};
		json!({ "jsonrpc": "2.0", "id": id, "result": { "outcome": outcome } })
	} else {
		tracing::debug!(method, "refused an agent request");
		json!({ "jsonrpc": "2.0", "id": id, "error": { "code": -32601, "message": "not supported" } })
	};
	let _ = writer.send(format!("{reply}\n"));
}

async fn read_stderr(stderr: ChildStderr, log: mpsc::UnboundedSender<String>) {
	let mut lines = BufReader::new(stderr).lines();
	while let Ok(Some(line)) = lines.next_line().await {
		let line = strip_ansi(&line);
		if line.contains("WARN") || line.contains("ERROR") {
			tracing::warn!(target: "grok", "{line}");
		} else {
			tracing::debug!(target: "grok", "{line}");
		}
		let _ = log.send(line);
	}
}

fn strip_ansi(line: &str) -> String {
	let mut out = String::with_capacity(line.len());
	let mut chars = line.chars();
	while let Some(c) = chars.next() {
		if c == '\u{1b}' {
			for c in chars.by_ref() {
				if c.is_ascii_alphabetic() {
					break;
				}
			}
		} else {
			out.push(c);
		}
	}
	out
}

#[cfg(test)]
mod tests {
	#[test]
	fn strips_color_codes() {
		assert_eq!(super::strip_ansi("\u{1b}[32m INFO\u{1b}[0m done"), " INFO done");
	}
}
