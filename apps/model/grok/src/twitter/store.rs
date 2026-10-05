//! The latest answer to each request, and the one refresh of it that may run at a time. Fast
//! response answers from here and refreshes behind (spec/architecture/grok/twitter.md, "Fast
//! response"). An answer that can no longer change is also written to the volume and never fetched
//! again ("Settled answers are kept").

use std::collections::HashMap;
use std::future::Future;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use axum::http::StatusCode;
use serde_json::{Value, json};
use tokio::sync::broadcast;

use super::fetch::Reply;
use super::job;

struct Latest {
	reply: Arc<Reply>,
	asked: Instant,
}

#[derive(Default)]
struct Inner {
	latest: HashMap<String, Latest>,
	refreshing: HashMap<String, broadcast::Sender<Arc<Reply>>>,
}

#[derive(Default)]
pub struct Store {
	inner: Mutex<Inner>,
	/// Where settled answers are kept; none in tests that do not need it.
	settled: Option<PathBuf>,
}

impl Store {
	pub fn new(settled: PathBuf) -> std::io::Result<Self> {
		std::fs::create_dir_all(&settled)?;
		Ok(Self { inner: Mutex::default(), settled: Some(settled) })
	}

	/// The latest answer to `key`, if there is one: in memory, or else settled on the volume.
	pub fn latest(&self, key: &str) -> Option<Arc<Reply>> {
		let mut inner = self.inner.lock().unwrap();
		if let Some(latest) = inner.latest.get_mut(key) {
			latest.asked = Instant::now();
			return Some(latest.reply.clone());
		}
		let reply = Arc::new(self.read_settled(key)?);
		inner.latest.insert(key.to_owned(), Latest { reply: reply.clone(), asked: Instant::now() });
		Some(reply)
	}

	/// Refreshes `key`, or joins the refresh already running for it; the receiver gets its reply.
	pub fn refresh<F>(self: &Arc<Self>, key: &str, fetch: F) -> broadcast::Receiver<Arc<Reply>>
	where
		F: Future<Output = Reply> + Send + 'static,
	{
		let mut inner = self.inner.lock().unwrap();
		if let Some(running) = inner.refreshing.get(key) {
			return running.subscribe();
		}
		let (tx, rx) = broadcast::channel(1);
		inner.refreshing.insert(key.to_owned(), tx.clone());
		drop(inner);
		let (store, key) = (self.clone(), key.to_owned());
		tokio::spawn(async move {
			// However the fetch ends, a panic included, the key is freed for the next refresh.
			let _guard = Refreshing { store: store.clone(), key: key.clone(), sender: tx.clone() };
			let reply = Arc::new(fetch.await);
			store.keep(&key, reply.clone());
			// Freed before the send, so a request that sees this reply and asks again refreshes anew.
			store.done(&key, &tx);
			let _ = tx.send(reply);
		});
		rx
	}

	fn keep(&self, key: &str, reply: Arc<Reply>) {
		let mut inner = self.inner.lock().unwrap();
		let holds_answer = inner.latest.get(key).is_some_and(|latest| latest.reply.is_answer());
		if reply.is_answer() || !holds_answer {
			if reply.is_settled() {
				self.write_settled(key, &reply);
			}
			inner.latest.insert(key.to_owned(), Latest { reply, asked: Instant::now() });
		}
	}

	fn path(&self, key: &str) -> Option<PathBuf> {
		Some(self.settled.as_ref()?.join(format!("{:016x}.json", fnv1a(key))))
	}

	/// A settled answer from the volume. The file carries its key, so two keys sharing a hash never
	/// answer for each other.
	fn read_settled(&self, key: &str) -> Option<Reply> {
		let stored: Value = serde_json::from_slice(&std::fs::read(self.path(key)?).ok()?).ok()?;
		if stored["key"] != key {
			return None;
		}
		Some(Reply {
			status: StatusCode::from_u16(stored["status"].as_u64()? as u16).ok()?,
			body: stored["body"].clone(),
			cache_control: job::IMMUTABLE,
		})
	}

	/// Written beside and moved into place, so a reader never sees half a file.
	fn write_settled(&self, key: &str, reply: &Reply) {
		let Some(path) = self.path(key) else { return };
		let stored = json!({ "key": key, "status": reply.status.as_u16(), "body": reply.body });
		let partial = path.with_extension("partial");
		let written =
			std::fs::write(&partial, stored.to_string()).and_then(|()| std::fs::rename(&partial, &path));
		if let Err(error) = written {
			tracing::warn!(%error, key, "could not keep a settled answer");
		}
	}

	/// Frees `key` for the next refresh, unless a later one already holds it.
	fn done(&self, key: &str, sender: &broadcast::Sender<Arc<Reply>>) {
		let mut inner = self.inner.lock().unwrap();
		if inner.refreshing.get(key).is_some_and(|running| running.same_channel(sender)) {
			inner.refreshing.remove(key);
		}
	}

	/// Forgets from memory what nobody has asked for in `idle`. Settled answers stay on the volume.
	pub fn sweep(&self, idle: Duration) {
		self.inner.lock().unwrap().latest.retain(|_, latest| latest.asked.elapsed() < idle);
	}
}

/// FNV-1a, 64 bits: a stable file name for a key of any length. Stability across releases is what
/// matters, which the standard library's hasher does not promise.
fn fnv1a(text: &str) -> u64 {
	text
		.bytes()
		.fold(0xcbf29ce484222325, |hash, byte| (hash ^ u64::from(byte)).wrapping_mul(0x100000001b3))
}

struct Refreshing {
	store: Arc<Store>,
	key: String,
	sender: broadcast::Sender<Arc<Reply>>,
}

impl Drop for Refreshing {
	fn drop(&mut self) {
		self.store.done(&self.key, &self.sender);
	}
}

#[cfg(test)]
mod tests {
	use axum::http::StatusCode;
	use serde_json::json;

	use super::*;
	use crate::twitter::job;

	fn reply(status: StatusCode) -> Reply {
		Reply { status, body: json!({}), cache_control: job::RECENT }
	}

	#[tokio::test]
	async fn one_refresh_runs_per_key() {
		let store = Arc::new(Store::default());
		let (release, wait) = tokio::sync::oneshot::channel::<()>();
		let mut first = store.refresh("k", async move {
			let _ = wait.await;
			reply(StatusCode::OK)
		});
		let mut second = store.refresh("k", async { panic!("a second refresh ran") });
		release.send(()).unwrap();
		assert_eq!(first.recv().await.unwrap().status, StatusCode::OK);
		assert_eq!(second.recv().await.unwrap().status, StatusCode::OK);
		assert_eq!(store.latest("k").unwrap().status, StatusCode::OK);
	}

	#[tokio::test]
	async fn a_failure_does_not_replace_an_answer() {
		let store = Arc::new(Store::default());
		store.refresh("k", async { reply(StatusCode::OK) }).recv().await.unwrap();
		store.refresh("k", async { reply(StatusCode::GATEWAY_TIMEOUT) }).recv().await.unwrap();
		assert_eq!(store.latest("k").unwrap().status, StatusCode::OK);
		store.refresh("gone", async { reply(StatusCode::GATEWAY_TIMEOUT) }).recv().await.unwrap();
		assert_eq!(
			store.latest("gone").unwrap().status,
			StatusCode::GATEWAY_TIMEOUT,
			"with nothing better, it is kept"
		);
	}

	#[test]
	fn forgets_what_nobody_asks_for() {
		let store = Store::default();
		store.keep("k", Arc::new(reply(StatusCode::OK)));
		store.sweep(Duration::ZERO);
		assert!(store.latest("k").is_none());
	}

	#[tokio::test]
	async fn a_settled_answer_outlives_memory() {
		let dir = std::env::temp_dir().join(format!("grok2api-settled-{}", std::process::id()));
		let store = Arc::new(Store::new(dir.clone()).unwrap());
		let settled = || Reply {
			status: StatusCode::OK,
			body: json!({ "data": 1 }),
			cache_control: job::IMMUTABLE,
		};
		store.refresh("old", async move { settled() }).recv().await.unwrap();
		store.refresh("new", async { reply(StatusCode::OK) }).recv().await.unwrap();
		store.sweep(Duration::ZERO);
		assert_eq!(
			store.latest("old").unwrap().body,
			json!({ "data": 1 }),
			"read back from the volume"
		);
		assert!(store.latest("new").is_none(), "a recent answer lives in memory only");
		let reopened = Store::new(dir.clone()).unwrap();
		assert!(reopened.latest("old").unwrap().is_settled(), "and survives a restart");
		std::fs::remove_dir_all(dir).unwrap();
	}
}
