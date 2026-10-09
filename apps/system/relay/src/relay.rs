//! One relay's state: what it holds of every node, its own node's snapshot, the runs mirrored,
//! and the stream every socket -- a neighbor's or a browser's -- is fed from.

use crate::cluster::{Carried, Cluster, Held, Versions};
use crate::host::{PAGE, Reader, Reading};
use crate::own::{Own, Part, RoundTrips};
use crate::runs::{Batch, Mirror, Shown, Store, StoreError};
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

/// A round trip not timed again within three pings is no longer current, and is left out.
const CURRENT: Duration = Duration::from_secs(3 * crate::mesh::PING.as_secs());

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

/// Every node's runs of the last 30 days, newest first: what `/runs` answers.
#[derive(Debug, Serialize)]
pub struct Runs {
	pub version: u32,
	/// The node whose relay answered.
	pub node: String,
	pub runs: Vec<Shown>,
}

pub struct Relay {
	node: String,
	secret: String,
	cluster: Mutex<Cluster>,
	own: Mutex<Own>,
	updates: broadcast::Sender<Update>,
	runs: Mirror,
	/// This node's own rows as each round finds them new or changed, for the mesh to push.
	batches: broadcast::Sender<Batch>,
	started: Instant,
	/// Which socket to each neighbor sends unasked; see `mesh::Speaking`.
	speakers: Mutex<BTreeMap<String, u64>>,
	conversations: AtomicU64,
	/// Each neighbor's latest round trip, and when it was timed.
	timed: Mutex<BTreeMap<String, (Duration, Instant)>>,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
	mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Relay {
	/// A relay over its runs' file, read before anything else is.
	pub fn new(node: String, secret: String, store: Store) -> Result<Arc<Self>, StoreError> {
		Ok(Arc::new(Self {
			runs: Mirror::open(node.clone(), store)?,
			node,
			secret,
			cluster: Mutex::default(),
			own: Mutex::default(),
			updates: broadcast::channel(BACKLOG).0,
			batches: broadcast::channel(BACKLOG).0,
			started: Instant::now(),
			speakers: Mutex::default(),
			conversations: AtomicU64::new(0),
			timed: Mutex::default(),
		}))
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

	/// One round of reading host, taken in as this node's snapshot with its round trips, and its
	/// events into the runs.
	pub fn observe(&self, reading: Reading) {
		let now = Timestamp::now();
		if let Ok(events) = &reading.events {
			self.events_read(events, now);
		}
		let round_trips = self.round_trips();
		let changed = {
			let mut own = lock(&self.own);
			let before: BTreeSet<Part> = own.stale().clone();
			let (changed, failed) = own.observe(reading, round_trips, now);
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

	/// This node's own events, as a round or the reading back reads them, into the runs; what is
	/// new or changed is pushed to the neighbors.
	fn events_read(&self, events: &[crate::host::Event], now: Timestamp) {
		if let Some(batch) = self.runs.observe(events, now) {
			let _ = self.batches.send(batch);
		}
	}

	pub fn versions(&self) -> Versions {
		lock(&self.cluster).versions()
	}

	/// Takes a neighbor's batch of runs; whether it did. Never this node's own, as `take`.
	pub fn take_runs(&self, batch: Batch) -> bool {
		self.runs.merge(batch)
	}

	pub fn run_versions(&self) -> Versions {
		self.runs.versions()
	}

	pub async fn lacking_runs(
		&self,
		theirs: &Versions,
		peer: &str,
	) -> Result<Vec<Batch>, StoreError> {
		self.runs.lacking(theirs, peer).await
	}

	pub fn subscribe_runs(&self) -> broadcast::Receiver<Batch> {
		self.batches.subscribe()
	}

	/// The window written, and what is past keeping dropped. See `runs::Mirror::write`.
	pub async fn write_runs(&self) -> Result<(), StoreError> {
		self.runs.write(Timestamp::now()).await
	}

	pub async fn runs(&self) -> Result<Runs, StoreError> {
		let runs = self.runs.listed(Timestamp::now()).await?;
		Ok(Runs { version: VERSION, node: self.node.clone(), runs })
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

	/// A round trip to `peer` just timed, on either socket to it; the latest replaces the last.
	pub fn timed(&self, peer: &str, round_trip: Duration) {
		lock(&self.timed).insert(peer.to_owned(), (round_trip, Instant::now()));
	}

	/// Each neighbor's latest round trip, a neighbor not timed lately left out.
	pub fn round_trips(&self) -> RoundTrips {
		current(&lock(&self.timed), Instant::now())
	}

	/// Once host has been read, or the grace is over.
	pub fn healthy(&self) -> bool {
		lock(&self.own).read() || self.started.elapsed() >= GRACE
	}
}

/// The round trips timed within `CURRENT` of `now`, in seconds to a ten-thousandth -- a tenth of a
/// millisecond, since a neighbor in the same place answers in under one; workspace spec/json.md,
/// "Keys are stable; values are cheap", has durations in seconds.
fn current(timed: &BTreeMap<String, (Duration, Instant)>, now: Instant) -> RoundTrips {
	timed
		.iter()
		.filter(|(_, (_, at))| now.saturating_duration_since(*at) < CURRENT)
		.map(|(peer, (round_trip, _))| {
			(peer.clone(), (round_trip.as_secs_f64() * 10_000.0).round() / 10_000.0)
		})
		.collect()
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

/// Reads this node's host back to the oldest row kept, a page at a time, into the runs: once, as
/// the relay starts, beside its rounds. A page host does not answer is asked again after a write's
/// wait. See spec/architecture/relay.md, "The runs, mirrored on every relay's disk".
pub async fn recall(relay: Arc<Relay>, source: Arc<dyn Reader>) {
	let mut before = None;
	let mut read = 0;
	loop {
		let page = match source.page(before).await {
			Ok(page) => page,
			Err(error) => {
				eprintln!("relay: reading host's earlier events: {error}");
				tokio::time::sleep(crate::runs::WRITE).await;
				continue;
			}
		};
		let now = Timestamp::now();
		relay.events_read(&page, now);
		read += page.len();
		let cutoff = now - crate::runs::KEPT;
		let past = page
			.iter()
			.any(|event| event.started_at.parse::<Timestamp>().is_ok_and(|started| started < cutoff));
		match page.iter().map(|event| event.id).min() {
			Some(oldest) if page.len() >= PAGE && read < crate::runs::MOST && !past => {
				before = Some(oldest);
			}
			_ => return,
		}
	}
}

/// Writes the runs every `every`, for as long as the relay runs. A refusal is logged and loses
/// nothing: the rows stay for the next.
pub async fn write(relay: Arc<Relay>, every: Duration) {
	let mut ticks = tokio::time::interval_at(tokio::time::Instant::now() + every, every);
	ticks.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
	loop {
		ticks.tick().await;
		if let Err(error) = relay.write_runs().await {
			eprintln!("relay: writing the runs: {error}");
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn relay(node: &str) -> Arc<Relay> {
		Relay::new(node.into(), "s3cret".into(), Store::memory().unwrap()).unwrap()
	}

	#[test]
	fn one_socket_to_a_neighbor_speaks_until_it_is_hushed() {
		let relay = relay("rdu");
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
	fn a_round_trip_is_in_milliseconds_and_left_out_once_it_is_old() {
		let now = Instant::now();
		let timed = BTreeMap::from([
			("tyo".into(), (Duration::from_micros(151_234), now - Duration::from_secs(1))),
			("buf".into(), (Duration::from_micros(460), now)),
			("gvx".into(), (Duration::from_millis(90), now - CURRENT)),
		]);
		assert_eq!(
			current(&timed, now),
			RoundTrips::from([("tyo".into(), 0.1512), ("buf".into(), 0.0005)])
		);
	}

	#[test]
	fn the_latest_round_trip_replaces_the_last() {
		let relay = relay("rdu");
		assert!(relay.round_trips().is_empty());
		relay.timed("tyo", Duration::from_millis(150));
		relay.timed("tyo", Duration::from_millis(149));
		assert_eq!(relay.round_trips(), RoundTrips::from([("tyo".into(), 0.149)]));
	}

	#[test]
	fn a_neighbors_word_on_this_node_is_not_taken() {
		let relay = relay("rdu");
		let carried = Carried { version: 9, snapshot: Arc::new(serde_json::json!({})) };
		assert!(!relay.take("rdu", carried.clone(), Some("tyo")));
		assert!(relay.take("tyo", carried, Some("tyo")));
		assert_eq!(relay.versions(), Versions::from([("tyo".into(), 9)]));
	}
}
