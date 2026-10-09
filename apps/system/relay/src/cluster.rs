//! Every node's newest snapshot as this relay holds it, and the comparison two relays make when
//! they meet. A snapshot is carried as the JSON its node wrote, so a relay passes on a field it is
//! too old to know.

use jiff::Timestamp;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::BTreeMap;
use std::sync::Arc;

/// What a relay holds of one node.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Held {
	pub version: u64,
	/// When its origin took this version, never later than this relay's clock: a version five
	/// minutes old is held as five minutes old, however it arrived. See spec/architecture/relay.md,
	/// "A node says it is leaving before it goes".
	pub heard_at: Timestamp,
	pub snapshot: Arc<Value>,
}

/// A node's snapshot as it travels between relays: when it was heard is each relay's own.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Carried {
	pub version: u64,
	pub snapshot: Arc<Value>,
}

/// Versions held, by node.
pub type Versions = BTreeMap<String, u64>;

#[derive(Debug, Default)]
pub struct Cluster {
	nodes: BTreeMap<String, Held>,
}

impl Cluster {
	/// Takes `carried` when it is newer than what is held of `node`, or `node` is new; whether it
	/// did. An equal version is the same snapshot heard twice.
	pub fn merge(&mut self, node: &str, carried: Carried, now: Timestamp) -> bool {
		if self.nodes.get(node).is_some_and(|held| held.version >= carried.version) {
			return false;
		}
		let heard_at = heard(carried.version, now);
		let held = Held { version: carried.version, heard_at, snapshot: carried.snapshot };
		self.nodes.insert(node.to_owned(), held);
		true
	}

	pub fn versions(&self) -> Versions {
		self.nodes.iter().map(|(node, held)| (node.clone(), held.version)).collect()
	}

	/// What `peer`, holding `theirs`, lacks: every node held newer here, but never `peer`'s own,
	/// of which it is the source.
	pub fn lacking(&self, theirs: &Versions, peer: &str) -> Vec<(String, Carried)> {
		self
			.nodes
			.iter()
			.filter(|(node, held)| {
				*node != peer && theirs.get(*node).is_none_or(|version| *version < held.version)
			})
			.map(|(node, held)| {
				(node.clone(), Carried { version: held.version, snapshot: held.snapshot.clone() })
			})
			.collect()
	}

	pub fn nodes(&self) -> &BTreeMap<String, Held> {
		&self.nodes
	}
}

/// When a version was taken by its origin, whose clock in milliseconds it is, capped at `now`.
fn heard(version: u64, now: Timestamp) -> Timestamp {
	let taken = i64::try_from(version).ok().and_then(|ms| Timestamp::from_millisecond(ms).ok());
	taken.map_or(now, |taken| taken.min(now))
}

#[cfg(test)]
mod tests {
	use super::*;
	use serde_json::json;

	fn carried(version: u64, said: &str) -> Carried {
		Carried { version, snapshot: Arc::new(json!({ "said": said })) }
	}

	fn at(seconds: i64) -> Timestamp {
		Timestamp::from_second(1_790_000_000 + seconds).unwrap()
	}

	/// The version a node's clock gives at `seconds`.
	fn taken(seconds: i64) -> u64 {
		u64::try_from(at(seconds).as_millisecond()).unwrap()
	}

	#[test]
	fn a_newer_version_replaces_an_older_one() {
		let mut cluster = Cluster::default();
		assert!(cluster.merge("rdu", carried(taken(0), "old"), at(0)));
		assert!(cluster.merge("rdu", carried(taken(3), "new"), at(3)));
		let held = &cluster.nodes()["rdu"];
		assert_eq!((held.version, held.heard_at), (taken(3), at(3)));
		assert_eq!(held.snapshot["said"], "new");
	}

	#[test]
	fn a_version_is_heard_when_its_origin_took_it_never_later_than_now() {
		let mut cluster = Cluster::default();
		// Handed on start by a neighbor still holding it: five minutes old, not heard now.
		cluster.merge("rdu", carried(taken(0), "stale"), at(300));
		assert_eq!(cluster.nodes()["rdu"].heard_at, at(0));
		// From a clock ahead of this one, heard now rather than in the future.
		cluster.merge("tyo", carried(taken(2), "ahead"), at(1));
		assert_eq!(cluster.nodes()["tyo"].heard_at, at(1));
	}

	#[test]
	fn an_older_or_equal_version_is_ignored() {
		let mut cluster = Cluster::default();
		cluster.merge("rdu", carried(taken(0), "new"), at(0));
		assert!(!cluster.merge("rdu", carried(taken(0) - 1, "old"), at(3)));
		assert!(!cluster.merge("rdu", carried(taken(0), "again"), at(6)));
		let held = &cluster.nodes()["rdu"];
		assert_eq!((held.heard_at, held.snapshot["said"].as_str()), (at(0), Some("new")));
	}

	#[test]
	fn an_unknown_node_is_added() {
		let mut cluster = Cluster::default();
		cluster.merge("rdu", carried(9, "rdu"), at(0));
		assert!(cluster.merge("tyo", carried(1, "tyo"), at(1)));
		assert_eq!(cluster.versions(), Versions::from([("rdu".into(), 9), ("tyo".into(), 1)]));
	}

	#[test]
	fn meeting_sends_each_side_exactly_what_it_lacks() {
		let mut here = Cluster::default();
		let mut there = Cluster::default();
		for (node, version) in [("rdu", 9), ("tyo", 4), ("buf", 7), ("gvx", 2)] {
			here.merge(node, carried(version, "here"), at(0));
		}
		// `there` is tyo: its own is newer there, buf is equal, gvx older, rdu missing, nrt its own.
		for (node, version) in [("tyo", 6), ("buf", 7), ("gvx", 1), ("nrt", 3)] {
			there.merge(node, carried(version, "there"), at(0));
		}

		let to_there: Vec<(String, u64)> = here
			.lacking(&there.versions(), "tyo")
			.into_iter()
			.map(|(node, carried)| (node, carried.version))
			.collect();
		assert_eq!(to_there, [("gvx".into(), 2), ("rdu".into(), 9)]);

		// tyo's own goes back however old it is here; nrt is new to `here`.
		let to_here: Vec<(String, u64)> = there
			.lacking(&here.versions(), "rdu")
			.into_iter()
			.map(|(node, carried)| (node, carried.version))
			.collect();
		assert_eq!(to_here, [("nrt".into(), 3), ("tyo".into(), 6)]);
	}
}
