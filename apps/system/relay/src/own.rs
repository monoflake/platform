//! This node's own snapshot, of which this relay is the one source: read from host every round,
//! and given a new version whenever what it says changes.

use crate::host::{App, Event, ReadError, Reading};
use jiff::Timestamp;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

/// How often host is read.
pub const EVERY: std::time::Duration = std::time::Duration::from_secs(3);

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Part {
	Events,
	Apps,
	Machine,
}

impl std::fmt::Display for Part {
	fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		formatter.write_str(match self {
			Self::Events => "events",
			Self::Apps => "apps",
			Self::Machine => "machine",
		})
	}
}

/// What a snapshot says; two that say the same are one version, whenever each was read.
#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct Content {
	pub events: Vec<Event>,
	pub apps: Vec<App>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub machine: Option<serde_json::Value>,
	/// The latest ping each neighbor answered on the mesh, timed; one not timed lately is absent.
	/// Not host's but this relay's own. See spec/architecture/relay.md, "The round trip to each
	/// neighbor".
	#[serde(skip_serializing_if = "BTreeMap::is_empty")]
	pub round_trip_ms: RoundTrips,
	/// The parts the last round failed to read, each held at what was read before.
	#[serde(skip_serializing_if = "BTreeSet::is_empty")]
	pub stale: BTreeSet<Part>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Snapshot {
	/// When the round that made this version read host.
	pub taken_at: Timestamp,
	#[serde(flatten)]
	pub content: Content,
}

/// This relay's round trip to each neighbor, in milliseconds, by neighbor.
pub type RoundTrips = BTreeMap<String, f64>;

/// The parts a round failed to read, each with why.
pub type Failures = Vec<(Part, ReadError)>;

#[derive(Debug, Default)]
pub struct Own {
	content: Content,
	version: u64,
	/// Whether events and apps have both been read in one round.
	read: bool,
}

impl Own {
	/// One round taken in, with the round trips as they stand: a new version and its snapshot when
	/// what it says changed. A failure is given back beside it with its part, for whoever logs.
	pub fn observe(
		&mut self,
		reading: Reading,
		round_trips: RoundTrips,
		now: Timestamp,
	) -> (Option<(u64, Snapshot)>, Failures) {
		let Reading { events, apps, machine } = reading;
		let mut next = self.content.clone();
		next.round_trip_ms = round_trips;
		let mut failed = Vec::new();
		kept(Part::Events, events, &mut next.events, &mut failed);
		kept(Part::Apps, apps, &mut next.apps, &mut failed);
		kept(Part::Machine, machine.map(Some), &mut next.machine, &mut failed);
		next.stale = failed.iter().map(|(part, _)| *part).collect();
		self.read |= !next.stale.contains(&Part::Events) && !next.stale.contains(&Part::Apps);

		if next == self.content && self.version != 0 {
			return (None, failed);
		}
		self.content = next;
		self.version = version_after(self.version, now);
		(Some((self.version, Snapshot { taken_at: now, content: self.content.clone() })), failed)
	}

	pub fn read(&self) -> bool {
		self.read
	}

	pub fn stale(&self) -> &BTreeSet<Part> {
		&self.content.stale
	}
}

/// `read` into `into`, or `into` left as it was and the failure noted.
fn kept<T>(part: Part, read: Result<T, ReadError>, into: &mut T, failed: &mut Failures) {
	match read {
		Ok(value) => *into = value,
		Err(error) => failed.push((part, error)),
	}
}

/// The millisecond it is, or one past the last when the clock has not moved on: a relay restarted
/// begins above every version it gave out before, which its neighbors still hold.
fn version_after(last: u64, now: Timestamp) -> u64 {
	let now = u64::try_from(now.as_millisecond()).unwrap_or(0);
	now.max(last + 1)
}

#[cfg(test)]
mod tests {
	use super::*;
	use serde_json::json;

	fn app(image: &str) -> App {
		App {
			name: "geo".into(),
			image: image.into(),
			deployed_at: "2026-10-05T08:00:00Z".into(),
			running: true,
			held: false,
			rollout: "replace".into(),
			label: None,
		}
	}

	fn reading(image: &str) -> Reading {
		Reading { events: Ok(vec![]), apps: Ok(vec![app(image)]), machine: Ok(json!({ "sample": 1 })) }
	}

	fn at(milliseconds: i64) -> Timestamp {
		Timestamp::from_millisecond(1_790_000_000_000 + milliseconds).unwrap()
	}

	#[test]
	fn a_version_moves_only_when_what_it_says_changes() {
		let mut own = Own::default();
		let (first, _) = own.observe(reading("geo:1"), RoundTrips::new(), at(0));
		let (first, snapshot) = first.unwrap();
		assert_eq!(first, 1_790_000_000_000);
		assert_eq!(snapshot.taken_at, at(0));
		assert!(own.observe(reading("geo:1"), RoundTrips::new(), at(3000)).0.is_none());
		let (second, snapshot) = own.observe(reading("geo:2"), RoundTrips::new(), at(6000)).0.unwrap();
		assert_eq!(second, first + 6000);
		assert_eq!(snapshot.content.apps[0].image, "geo:2");
	}

	#[test]
	fn a_version_climbs_when_the_clock_does_not() {
		assert_eq!(version_after(1_790_000_000_500, at(0)), 1_790_000_000_501);
		// Restarted: the last is forgotten, and the clock alone puts it above what it gave out.
		assert_eq!(version_after(0, at(0)), 1_790_000_000_000);
	}

	#[test]
	fn a_failed_read_keeps_what_was_read_and_says_it_is_stale() {
		let mut own = Own::default();
		own.observe(reading("geo:1"), RoundTrips::new(), at(0));
		let failing = Reading {
			events: Ok(vec![]),
			apps: Err(ReadError::Slow(std::time::Duration::from_secs(5))),
			machine: Ok(json!({ "sample": 1 })),
		};
		let (changed, failed) = own.observe(failing, RoundTrips::new(), at(3000));
		let (_, snapshot) = changed.unwrap();
		assert_eq!(snapshot.content.apps, [app("geo:1")]);
		assert_eq!(snapshot.content.stale, BTreeSet::from([Part::Apps]));
		assert_eq!(failed.len(), 1);
		let written = serde_json::to_value(&snapshot).unwrap();
		assert_eq!(written["stale"], json!(["apps"]));
		assert_eq!(written["machine"], json!({ "sample": 1 }));
		assert!(written.get("taken_at").is_some());
	}

	#[test]
	fn the_round_trips_are_carried_and_absent_while_there_are_none() {
		let mut own = Own::default();
		let (_, snapshot) = own.observe(reading("geo:1"), RoundTrips::new(), at(0)).0.unwrap();
		assert!(serde_json::to_value(&snapshot).unwrap().get("round_trip_ms").is_none());
		let timed = RoundTrips::from([("tyo".into(), 151.2), ("buf".into(), 18.0)]);
		let (_, snapshot) = own.observe(reading("geo:1"), timed, at(3000)).0.unwrap();
		let written = serde_json::to_value(&snapshot).unwrap();
		assert_eq!(written["round_trip_ms"], json!({ "buf": 18.0, "tyo": 151.2 }));
	}

	#[test]
	fn host_counts_as_read_once_events_and_apps_both_are() {
		let mut own = Own::default();
		fn unread<T>() -> Result<T, ReadError> {
			Err(ReadError::Slow(std::time::Duration::from_secs(5)))
		}
		let neither = Reading { events: unread(), apps: Ok(vec![]), machine: unread() };
		own.observe(neither, RoundTrips::new(), at(0));
		assert!(!own.read());
		let both = Reading { events: Ok(vec![]), apps: Ok(vec![]), machine: unread() };
		own.observe(both, RoundTrips::new(), at(3000));
		assert!(own.read());
	}
}
