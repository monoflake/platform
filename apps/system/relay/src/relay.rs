//! One relay's state: what it holds of every node, its own node's snapshot, and the stream every
//! socket -- a neighbor's or a browser's -- is fed from.

use crate::cluster::{Carried, Cluster, Held, Versions};
use crate::host::Reading;
use crate::own::{Own, Part};
use jiff::Timestamp;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::{Duration, Instant};
use tokio::sync::broadcast;

/// The version of what the mesh and a browser are sent, read first by either. See the workspace's
/// spec/json.md, "A contract has a version, and it is the first thing read".
pub const VERSION: u32 = 1;

/// How long `/health` waits for the first read of host before it answers healthy regardless: a
/// relay that cannot read its own node still carries every other node.
pub const GRACE: Duration = Duration::from_secs(30);

/// Every node changing every few seconds; a socket further behind than this is caught up whole.
const BACKLOG: usize = 256;

/// A node's newer snapshot, taken here.
#[derive(Debug, Clone)]
pub struct Update {
	pub node: String,
	pub held: Held,
}

/// Every node at once: what `/state` answers and a browser's socket opens with.
#[derive(Debug, Serialize)]
pub struct State {
	pub version: u32,
	/// The node whose relay answered.
	pub node: String,
	pub nodes: BTreeMap<String, Held>,
}

pub struct Relay {
	node: String,
	secret: String,
	cluster: Mutex<Cluster>,
	own: Mutex<Own>,
	updates: broadcast::Sender<Update>,
	started: Instant,
	/// Which socket to each neighbor sends unasked; see `mesh::Speaking`.
	speakers: Mutex<BTreeMap<String, u64>>,
	conversations: AtomicU64,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
	mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Relay {
	pub fn new(node: String, secret: String) -> Arc<Self> {
		Arc::new(Self {
			node,
			secret,
			cluster: Mutex::default(),
			own: Mutex::default(),
			updates: broadcast::channel(BACKLOG).0,
			started: Instant::now(),
			speakers: Mutex::default(),
			conversations: AtomicU64::new(0),
		})
	}

	pub fn node(&self) -> &str {
		&self.node
	}

	pub fn secret(&self) -> &str {
		&self.secret
	}

	pub fn subscribe(&self) -> broadcast::Receiver<Update> {
		self.updates.subscribe()
	}

	/// Takes a snapshot of `node` when it is newer than what is held, and passes it on; whether it
	/// did. `via` is the neighbor it came from, whose word on this node is never taken: this relay is
	/// its one source.
	pub fn take(&self, node: &str, carried: Carried, via: Option<&str>) -> bool {
		if via.is_some() && node == self.node {
			return false;
		}
		let mut cluster = lock(&self.cluster);
		if !cluster.merge(node, carried, Timestamp::now()) {
			return false;
		}
		// Sent under the lock, so every socket sees one node's versions in the order taken.
		let held = cluster.nodes()[node].clone();
		let _ = self.updates.send(Update { node: node.to_owned(), held });
		true
	}

	/// One round of reading host, taken in as this node's snapshot.
	pub fn observe(&self, reading: Reading) {
		let now = Timestamp::now();
		let changed = {
			let mut own = lock(&self.own);
			let before: BTreeSet<Part> = own.stale().clone();
			let (changed, failed) = own.observe(reading, now);
			for (part, error) in &failed {
				if !before.contains(part) {
					eprintln!("relay: reading host's {part}: {error}");
				}
			}
			for part in before.difference(own.stale()) {
				eprintln!("relay: reading host's {part} again");
			}
			changed
		};
		if let Some((version, snapshot)) = changed {
			let snapshot = serde_json::to_value(snapshot).expect("a snapshot is a tree of strings");
			self.take(&self.node, Carried { version, snapshot: Arc::new(snapshot) }, None);
		}
	}

	pub fn versions(&self) -> Versions {
		lock(&self.cluster).versions()
	}

	pub fn lacking(&self, theirs: &Versions, peer: &str) -> Vec<(String, Carried)> {
		lock(&self.cluster).lacking(theirs, peer)
	}

	pub fn state(&self) -> State {
		let nodes = lock(&self.cluster).nodes().clone();
		State { version: VERSION, node: self.node.clone(), nodes }
	}

	/// A number for a socket to a neighbor, its own among them.
	pub fn conversation(&self) -> u64 {
		self.conversations.fetch_add(1, Ordering::Relaxed)
	}

	/// Whether `conversation` is the socket to `peer` that sends unasked: the first to ask is, until
	/// it is hushed.
	pub fn speaks(&self, peer: &str, conversation: u64) -> bool {
		*lock(&self.speakers).entry(peer.to_owned()).or_insert(conversation) == conversation
	}

	pub fn hush(&self, peer: &str, conversation: u64) {
		let mut speakers = lock(&self.speakers);
		if speakers.get(peer) == Some(&conversation) {
			speakers.remove(peer);
		}
	}

	/// Once host has been read, or the grace is over.
	pub fn healthy(&self) -> bool {
		lock(&self.own).read() || self.started.elapsed() >= GRACE
	}
}

/// Reads host every `every`, for as long as the relay runs.
pub async fn watch(relay: Arc<Relay>, source: Arc<dyn crate::host::Reader>, every: Duration) {
	let mut ticks = tokio::time::interval(every);
	ticks.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
	loop {
		ticks.tick().await;
		relay.observe(source.read().await);
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn one_socket_to_a_neighbor_speaks_until_it_is_hushed() {
		let relay = Relay::new("rdu".into(), "s3cret".into());
		let (first, second) = (relay.conversation(), relay.conversation());
		assert!(relay.speaks("tyo", first));
		assert!(!relay.speaks("tyo", second));
		assert!(relay.speaks("buf", second));
		relay.hush("tyo", second);
		assert!(relay.speaks("tyo", first));
		relay.hush("tyo", first);
		assert!(relay.speaks("tyo", second));
	}

	#[test]
	fn a_neighbors_word_on_this_node_is_not_taken() {
		let relay = Relay::new("rdu".into(), "s3cret".into());
		let carried = Carried { version: 9, snapshot: Arc::new(serde_json::json!({})) };
		assert!(!relay.take("rdu", carried.clone(), Some("tyo")));
		assert!(relay.take("tyo", carried, Some("tyo")));
		assert_eq!(relay.versions(), Versions::from([("tyo".into(), 9)]));
	}
}
