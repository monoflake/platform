//! The idle sessions, and which request continues which. See spec/architecture/grok/sessions.md.

use std::sync::Mutex;
use std::time::{Duration, Instant};

use crate::message::MessageKey;

/// A session not answering anything right now, with the conversation it has seen. `A` is the agent
/// it lives in: a session stays with the agent that made it, including one a newer CLI has since
/// replaced (spec/architecture/grok/deployment.md), and holding it is what keeps that agent alive.
pub struct Session<A> {
	pub agent: A,
	pub id: String,
	pub system: String,
	pub history: Vec<MessageKey>,
	pub model: String,
	pub effort: Option<String>,
	/// The id the session's latest answer went out under.
	pub last_reply: Option<String>,
	last_used: Instant,
}

impl<A> Session<A> {
	pub fn new(agent: A, id: String, system: String, model: String) -> Self {
		Self {
			agent,
			id,
			system,
			history: Vec::new(),
			model,
			effort: None,
			last_reply: None,
			last_used: Instant::now(),
		}
	}
}

/// A session is either here, idle, or held by the one request it is answering. Taking it out to
/// answer is what keeps two requests from continuing one conversation at once: the second finds
/// nothing to match and starts a session of its own.
pub struct Pool<A> {
	idle: Mutex<Vec<Session<A>>>,
	idle_for: Duration,
}

impl<A> Pool<A> {
	pub fn new(idle_for: Duration) -> Self {
		Self { idle: Mutex::new(Vec::new()), idle_for }
	}

	/// Takes the idle session whose conversation is exactly the one given, if there is one.
	pub fn claim(&self, system: &str, history: &[MessageKey]) -> Option<Session<A>> {
		let mut idle = self.idle.lock().unwrap();
		let index =
			idle.iter().position(|session| session.system == system && session.history == history)?;
		Some(idle.swap_remove(index))
	}

	/// Takes the idle session whose latest answer went out as `reply`, if there is one.
	pub fn claim_reply(&self, reply: &str) -> Option<Session<A>> {
		let mut idle = self.idle.lock().unwrap();
		let index = idle.iter().position(|session| session.last_reply.as_deref() == Some(reply))?;
		Some(idle.swap_remove(index))
	}

	/// Returns a session that answered, to be continued by whichever request extends it next.
	pub fn release(&self, mut session: Session<A>) {
		session.last_used = Instant::now();
		self.idle.lock().unwrap().push(session);
	}

	/// Removes the sessions idle past the limit, to be closed.
	pub fn take_expired(&self) -> Vec<Session<A>> {
		let mut idle = self.idle.lock().unwrap();
		let (expired, kept) =
			idle.drain(..).partition(|session| session.last_used.elapsed() >= self.idle_for);
		*idle = kept;
		expired
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::message::Message;

	fn session(id: &str, history: &[&str]) -> Session<()> {
		let mut session = Session::new((), id.into(), String::new(), "grok-4.7".into());
		session.history = history.iter().map(|text| Message::assistant((*text).into()).key()).collect();
		session
	}

	#[test]
	fn claims_only_an_exact_conversation() {
		let pool = Pool::new(Duration::from_secs(60));
		pool.release(session("a", &["one", "two"]));
		let shorter = [Message::assistant("one".into()).key()];
		assert!(pool.claim("", &shorter).is_none());
		let exact = [Message::assistant("one".into()).key(), Message::assistant("two".into()).key()];
		assert_eq!(pool.claim("", &exact).unwrap().id, "a");
		assert!(pool.claim("", &exact).is_none(), "a claimed session is no longer idle");
	}

	#[test]
	fn the_system_prompt_is_part_of_the_match() {
		let pool = Pool::new(Duration::from_secs(60));
		pool.release(session("a", &[]));
		assert!(pool.claim("another system prompt", &[]).is_none());
	}

	#[test]
	fn expires_what_idled_too_long() {
		let pool = Pool::new(Duration::ZERO);
		pool.release(session("a", &[]));
		let expired = pool.take_expired();
		assert_eq!(expired.len(), 1);
		assert_eq!(expired[0].id, "a");
	}

	#[test]
	fn claims_by_the_reply_it_last_gave() {
		let pool = Pool::new(Duration::from_secs(60));
		let mut answered = session("a", &["one"]);
		answered.last_reply = Some("resp_1".into());
		pool.release(answered);
		assert!(pool.claim_reply("resp_0").is_none());
		assert_eq!(pool.claim_reply("resp_1").unwrap().id, "a");
	}
}
