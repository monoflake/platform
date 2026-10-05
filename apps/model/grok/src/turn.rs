//! One chat completion: find or make the session, send the prompt, stream what comes back.

use std::sync::{Arc, RwLock};

use anyhow::Result;
use serde_json::{Value, json};
use tokio::sync::mpsc;

use crate::agent::Agent;
use crate::environment::{Environment, Profile};
use crate::message::{Conversation, Message};
use crate::sessions;
use crate::transcript::render_history;

/// Put ahead of the client's own system prompt. The model reaches for any tool it has, and the
/// one the profile keeps is never useful to a chat; spec/architecture/grok/bridge.md.
const BASE_SYSTEM: &str = "You are a helpful assistant. You have no tools: answer directly, and never \
	call, search for or mention a tool.";

type Session = sessions::Session<Arc<Agent>>;

/// Everything a completion needs, shared by every request.
pub struct Bridge {
	/// The agent new sessions are made in. Replaced when a newer CLI passes its check; the one it
	/// replaces lives on in the sessions it holds (spec/architecture/grok/deployment.md).
	current: RwLock<Arc<Agent>>,
	pool: sessions::Pool<Arc<Agent>>,
	pub environment: Environment,
}

pub struct Request {
	pub conversation: Conversation,
	pub model: String,
	/// Honored when the model offers it, ignored when not (spec/architecture/grok/api.md).
	pub effort: Option<String>,
	/// A JSON Schema the answer must match (spec/architecture/grok/api.md, "Structured output").
	pub schema: Option<Value>,
	/// The id this answer is returned under; a later request may name it to continue.
	pub reply_id: String,
	/// The reply this request continues, when it says so rather than resending the conversation:
	/// the Responses API's `previous_response_id` (spec/architecture/grok/sessions.md).
	pub previous: Option<String>,
}

/// A request named a reply to continue that no idle session holds.
#[derive(Debug)]
pub struct UnknownReply(pub String);

impl std::fmt::Display for UnknownReply {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		write!(f, "no conversation continues from {}; it expired or was never made", self.0)
	}
}

impl std::error::Error for UnknownReply {}

/// What a turn produces, in the agent's terms; each API shape renders it its own way.
pub enum Update {
	Reasoning(String),
	Content(String),
	Done(Outcome),
	Failed(String),
}

pub struct Outcome {
	/// ACP's stop reason: `end_turn`, `max_tokens`, `refusal`, `cancelled`, ...
	pub stop_reason: String,
	pub usage: Usage,
}

/// Token counts as the agent reports them. `input` is the whole prompt, cache reads included.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct Usage {
	pub input: u64,
	pub output: u64,
	pub cache_read: u64,
	pub cache_creation: u64,
	pub reasoning: u64,
}

impl Usage {
	fn from_meta(meta: &Value) -> Self {
		let count = |value: &Value| value.as_u64().unwrap_or(0);
		Self {
			input: count(&meta["inputTokens"]),
			output: count(&meta["outputTokens"]),
			cache_read: count(&meta["cachedReadTokens"]),
			cache_creation: count(&meta["usage"]["cacheCreationTokens"]),
			reasoning: count(&meta["reasoningTokens"]),
		}
	}
}

impl Bridge {
	pub fn new(agent: Arc<Agent>, environment: Environment, idle_for: std::time::Duration) -> Self {
		Self { current: RwLock::new(agent), pool: sessions::Pool::new(idle_for), environment }
	}

	pub fn agent(&self) -> Arc<Agent> {
		self.current.read().unwrap().clone()
	}

	/// Makes `agent` the one new sessions go to.
	pub fn replace(&self, agent: Arc<Agent>) {
		*self.current.write().unwrap() = agent;
	}

	/// Prepares the session and starts the prompt. An error here is the request's, returned before
	/// any byte of the response; a failure after it arrives as `Update::Failed`.
	pub async fn start(self: &Arc<Self>, request: Request) -> Result<mpsc::Receiver<Update>> {
		let Request { conversation, model, effort, schema, reply_id, previous } = request;
		let history = conversation.history_keys();
		let claimed = match &previous {
			Some(previous) => {
				let mut session =
					self.pool.claim_reply(previous).ok_or_else(|| UnknownReply(previous.clone()))?;
				// What the request carries ahead of its last message is new to the session.
				session.history.extend(history.iter().cloned());
				Some((session, seed_blocks(&conversation.history)))
			}
			None => self.pool.claim(&conversation.system, &history).map(|session| (session, Vec::new())),
		};
		let (mut session, mut blocks, continued) = match claimed {
			Some((session, blocks)) => (session, blocks, true),
			None => {
				let agent = self.agent();
				let id = agent
					.new_session(
						&self.environment.workspace,
						Profile::Chat,
						&system_prompt(&conversation.system),
					)
					.await?;
				let model = agent.info.default_model.clone();
				let mut session = Session::new(agent, id, conversation.system.clone(), model);
				session.history = history;
				(session, seed_blocks(&conversation.history), false)
			}
		};
		if let Err(error) = self.configure(&mut session, &model, effort.as_deref()).await {
			self.discard(session);
			return Err(error);
		}
		blocks.extend(conversation.last.parts.iter().map(|part| part.block()));
		tracing::info!(
			session = %session.id,
			continued,
			turns = session.history.len() / 2 + 1,
			model = %session.model,
			cli = %session.agent.info.version,
			"completion"
		);

		session.last_reply = Some(reply_id);
		let (tx, rx) = mpsc::channel(64);
		let bridge = self.clone();
		tokio::spawn(
			async move { bridge.answer(session, conversation.last, blocks, schema, tx).await },
		);
		Ok(rx)
	}

	async fn configure(
		&self,
		session: &mut Session,
		model: &str,
		effort: Option<&str>,
	) -> Result<()> {
		if session.model != model {
			session.agent.set_option(&session.id, "model", model).await?;
			session.model = model.to_owned();
		}
		if let Some(effort) = effort
			&& session.effort.as_deref() != Some(effort)
		{
			match session.agent.set_option(&session.id, "reasoning_effort", effort).await {
				Ok(()) => session.effort = Some(effort.to_owned()),
				Err(error) => {
					tracing::debug!(%error, effort, "ignored a reasoning effort the model does not offer")
				}
			}
		}
		Ok(())
	}

	async fn answer(
		self: Arc<Self>,
		mut session: Session,
		last: Message,
		blocks: Vec<Value>,
		schema: Option<Value>,
		tx: mpsc::Sender<Update>,
	) {
		let (agent, id) = (session.agent.clone(), session.id.clone());
		let mut updates = agent.subscribe(&id);
		let prompt = agent.prompt(&id, blocks, schema.as_ref());
		tokio::pin!(prompt);
		let mut content = String::new();
		let mut client_gone = false;
		let result = loop {
			tokio::select! {
				result = &mut prompt => break result,
				Some(update) = updates.recv() => {
					if !forward(&update, &mut content, &tx).await && !client_gone {
						client_gone = true;
						tracing::info!(session = %id, "the client went away; cancelling");
						agent.cancel(&id);
					}
				}
			}
		};
		// The agent writes a prompt's updates before its result, but the two race here.
		while let Ok(update) = updates.try_recv() {
			forward(&update, &mut content, &tx).await;
		}
		agent.unsubscribe(&id);

		match result {
			Ok(result) if !client_gone => {
				session.history.push(last.key());
				session.history.push(Message::assistant(content).key());
				self.pool.release(session);
				let stop_reason = result["stopReason"].as_str().unwrap_or("end_turn").to_owned();
				let usage = Usage::from_meta(&result["_meta"]);
				let _ = tx.send(Update::Done(Outcome { stop_reason, usage })).await;
			}
			// A cancelled or failed turn leaves the session holding a conversation nobody has.
			Ok(result) => {
				tracing::info!(session = %id, stop = %result["stopReason"], "the turn was cancelled; the session is discarded");
				self.discard(session);
			}
			Err(error) => {
				self.discard(session);
				let _ = tx.send(Update::Failed(error.to_string())).await;
			}
		}
	}

	fn discard(&self, session: Session) {
		tokio::spawn(async move { session.agent.close(&session.id).await });
	}

	/// Closes the sessions idle past the limit; run on a timer. A replaced agent goes when the
	/// last of its sessions does.
	pub async fn expire(&self) {
		for session in self.pool.take_expired() {
			session.agent.close(&session.id).await;
		}
	}
}

/// The earlier turns rendered for a session that has not seen them, as the prompt's first block.
fn seed_blocks(history: &[Message]) -> Vec<Value> {
	let seed = render_history(history);
	if seed.is_empty() { Vec::new() } else { vec![json!({ "type": "text", "text": seed })] }
}

fn system_prompt(client: &str) -> String {
	if client.trim().is_empty() {
		BASE_SYSTEM.to_owned()
	} else {
		format!("{BASE_SYSTEM}\n\n{client}")
	}
}

/// Passes one `session/update` on; false when the client is no longer listening.
async fn forward(update: &Value, content: &mut String, tx: &mpsc::Sender<Update>) -> bool {
	let text = || update["content"]["text"].as_str().unwrap_or_default().to_owned();
	let message = match update["sessionUpdate"].as_str() {
		Some("agent_message_chunk") => {
			let text = text();
			content.push_str(&text);
			Update::Content(text)
		}
		Some("agent_thought_chunk") => Update::Reasoning(text()),
		Some("tool_call") => {
			tracing::warn!(tool = %update["title"], "the model called a tool");
			return true;
		}
		_ => return true,
	};
	tx.send(message).await.is_ok()
}
