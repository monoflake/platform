//! Every node's history a minute at a time: whether host was read, which apps were down, how far
//! its neighbors were, and whether it said it was leaving. A node's minutes are its own relay's,
//! versioned and spread on the mesh as its runs are, and kept in the same file, folded into hours
//! and days as they age. `/history` answers them with the runs, from the file. See
//! spec/architecture/relay.md, "Each node's minutes, kept for a year".

pub mod answer;
pub mod fold;
pub mod outcomes;
pub mod store;
pub mod tally;

use crate::cluster::Versions;
use crate::host::Reading;
use crate::own::RoundTrips;
use crate::presence::Reason;
use crate::runs::{Shared, Shown, StoreError, blocking, lock};
use crate::window::{self, Lack, Versioned, Window};
use answer::{Answering, Asked, History};
use jiff::Timestamp;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::sync::Mutex;
use std::time::Duration;
use tally::Tally;

/// A minute, an hour and a day, in milliseconds, each a tier's unit.
pub const MINUTE: i64 = 60_000;
pub const HOUR: i64 = 60 * MINUTE;
pub const DAY: i64 = 24 * HOUR;

/// The rounds a minute holds, one every `own::EVERY`: its beats due.
pub const ROUNDS: u32 = 20;

pub const MINUTES_KEPT: Duration = Duration::from_secs(2 * 24 * 60 * 60);
pub const HOURS_KEPT: Duration = Duration::from_secs(30 * 24 * 60 * 60);
pub const DAYS_KEPT: Duration = Duration::from_secs(400 * 24 * 60 * 60);

/// The start of the `unit` that `at` falls in, both in milliseconds.
pub fn floor(at: i64, unit: i64) -> i64 {
	at - at.rem_euclid(unit)
}

/// The start of the minute it is at `now`, in milliseconds.
pub fn minute_of(now: Timestamp) -> i64 {
	floor(now.as_millisecond(), MINUTE)
}

/// One minute of one node, written by its relay as the minute ends.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Minute {
	/// Its start, in its origin's clock, in milliseconds.
	pub at: i64,
	/// The rounds in it that read host, of `ROUNDS`.
	pub beats: u32,
	/// Each app that should have run and did not, and in how many of the minute's rounds.
	#[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
	pub down: BTreeMap<String, u32>,
	/// How many apps were stopped on purpose.
	#[serde(default, skip_serializing_if = "is_zero")]
	pub held: u32,
	/// Each neighbor's mean round trip over it, in seconds; one not timed is absent.
	#[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
	pub round_trip: RoundTrips,
	/// Why, where the relay said in it that it was leaving.
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub leaving: Option<Reason>,
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn is_zero(count: &u32) -> bool {
	*count == 0
}

impl Minute {
	/// This minute, counted after a restart within it, joined with what was written of it before:
	/// the relay is its one writer, so the two are one minute.
	fn joined(self, before: &Minute) -> Minute {
		let mut round_trip = before.round_trip.clone();
		round_trip.extend(self.round_trip);
		let mut down = before.down.clone();
		for (app, rounds) in self.down {
			let held = down.entry(app).or_default();
			*held = (*held + rounds).min(ROUNDS);
		}
		Minute {
			at: self.at,
			beats: (self.beats + before.beats).min(ROUNDS),
			down,
			held: self.held.max(before.held),
			round_trip,
			leaving: self.leaving.or(before.leaving),
		}
	}
}

/// A minute as it travels between relays, with the version its origin gave it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Row {
	pub version: u64,
	#[serde(flatten)]
	pub minute: Minute,
}

impl Versioned for Row {
	fn version(&self) -> u64 {
		self.version
	}

	fn key(&self) -> i64 {
		self.minute.at
	}

	fn kept(&self) -> bool {
		self.minute.at.rem_euclid(MINUTE) == 0
	}
}

pub type Batch = window::Batch<Row>;

/// The minutes: the window, this node's minute being counted, and the file.
pub struct Book {
	window: Mutex<Window<Row>>,
	tally: Mutex<Tally>,
	/// This node's newest minute the file held as the relay started, which the first minute after
	/// a restart within it joins.
	before: Mutex<Option<Minute>>,
	store: Shared,
}

impl Book {
	pub fn open(node: String, store: Shared) -> Result<Self, StoreError> {
		let (held, before) = {
			let mut store = lock(&store);
			let connection = store.connection();
			(store::held(connection)?, store::last(connection, &node)?)
		};
		Ok(Self {
			window: Mutex::new(Window::new(node, held)),
			tally: Mutex::default(),
			before: Mutex::new(before),
			store,
		})
	}

	/// One round of host read: the minute before, as a batch for the neighbors, once it ends.
	pub fn round(
		&self,
		reading: &Reading,
		round_trips: &RoundTrips,
		now: Timestamp,
	) -> Option<Batch> {
		let read = reading.events.is_ok() && reading.apps.is_ok();
		let apps = reading.apps.as_deref().ok();
		let ended = lock(&self.tally).round(read, apps, round_trips, now)?;
		Some(self.own(vec![ended], now))
	}

	/// The minute the relay says it is leaving in, ended now, as a batch for the neighbors.
	pub fn leave(&self, reason: Reason, now: Timestamp) -> Batch {
		let ended = lock(&self.tally).leave(reason, now);
		self.own(ended, now)
	}

	fn own(&self, minutes: Vec<Minute>, now: Timestamp) -> Batch {
		let mut before = lock(&self.before);
		let minutes: Vec<Minute> = minutes
			.into_iter()
			.map(|minute| match before.take() {
				Some(earlier) if earlier.at == minute.at => minute.joined(&earlier),
				_ => minute,
			})
			.collect();
		let made = |version| minutes.into_iter().map(|minute| Row { version, minute }).collect();
		lock(&self.window).own(now, made)
	}

	pub fn merge(&self, batch: Batch) -> bool {
		lock(&self.window).merge(batch)
	}

	pub fn versions(&self) -> Versions {
		lock(&self.window).versions()
	}

	/// What `peer`, holding `theirs`, lacks, from the file where memory no longer holds it all.
	pub async fn lacking(&self, theirs: &Versions, peer: &str) -> Result<Vec<Batch>, StoreError> {
		let lacking = lock(&self.window).lacking(theirs, peer);
		let mut batches = Vec::with_capacity(lacking.len());
		for lack in lacking {
			batches.push(match lack {
				Lack::Held(batch) => batch,
				Lack::Behind(batch) => {
					let (node, above) = (batch.node.clone(), batch.above);
					let written =
						blocking(&self.store, move |store| store::above(store.connection(), &node, above))
							.await?;
					let both = written.into_iter().chain(batch.rows).map(|row| (String::new(), row));
					Batch { rows: window::newest(both).into_values().collect(), ..batch }
				}
			});
		}
		Ok(batches)
	}

	/// Writes what the window holds unwritten, folds and drops what is past keeping, then lets go
	/// of what memory no longer needs. A refusal leaves every row unwritten for the next.
	pub async fn write(&self, now: Timestamp) -> Result<(), StoreError> {
		let unwritten = lock(&self.window).unwritten();
		let taken = blocking(&self.store, move |store| {
			store::keep(store.connection(), &unwritten, now.as_millisecond())?;
			Ok(unwritten)
		})
		.await?;
		let mut window = lock(&self.window);
		window.written(&taken);
		window.evict(now, crate::runs::WINDOW);
		Ok(())
	}

	/// Every node over what `asked` spans, from the file and the window, the runs `runs` and the
	/// days counted of them.
	pub async fn history(
		&self,
		node: String,
		asked: Asked,
		runs: Vec<(i64, Shown)>,
		now: Timestamp,
	) -> Result<History, StoreError> {
		let mut answering = Answering::new(asked, now.as_millisecond());
		let (from, until) = answering.span();
		let held: Vec<(String, Row)> = lock(&self.window)
			.rows()
			.filter(|(_, row)| (from..until).contains(&row.minute.at))
			.map(|(node, row)| (node.to_owned(), row.clone()))
			.collect();
		let answering = blocking(&self.store, move |store| {
			let connection = store.connection();
			let skip = held.iter().map(|(node, row)| (node.clone(), row.minute.at)).collect();
			store::each(connection, from, until, &skip, |node, at, length, fold| {
				answering.held(node, at, length, fold);
			})?;
			for (node, row) in &held {
				answering.minute(node, &row.minute);
			}
			answering.first(store::first(connection)?);
			answering.tails(store::tails(connection, from)?);
			answering.days(outcomes::read(connection, None, from, until)?);
			Ok(answering)
		})
		.await?;
		let rows = runs.iter().map(|(_, shown)| (shown.node.as_str(), &shown.event));
		Ok(answering.runs(outcomes::runs(rows)).answered(node))
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::host::App;
	use crate::runs::{Store, shared};

	/// A moment `seconds` into a minute on 2026-10-09.
	fn at(seconds: i64) -> Timestamp {
		Timestamp::from_second(1_791_499_980 + seconds).unwrap()
	}

	fn reading(running: bool) -> Reading {
		let app = App {
			name: "geo".into(),
			image: "geo:1".into(),
			deployed_at: "2026-10-05T08:00:00Z".into(),
			running,
			held: false,
			rollout: "replace".into(),
			label: None,
		};
		Reading { events: Ok(vec![]), apps: Ok(vec![app]), machine: Ok(serde_json::json!({})) }
	}

	#[tokio::test]
	async fn a_relay_back_within_the_minute_it_left_in_keeps_its_word_of_leaving() {
		let store = shared(Store::memory().unwrap());
		let book = Book::open("rdu".into(), store.clone()).unwrap();
		book.round(&reading(true), &RoundTrips::new(), at(3));
		let left = book.leave(Reason::Upgrade, at(10));
		assert_eq!(left.rows.len(), 1);
		assert_eq!(
			(left.rows[0].minute.beats, left.rows[0].minute.leaving),
			(1, Some(Reason::Upgrade))
		);
		book.write(at(10)).await.unwrap();

		let book = Book::open("rdu".into(), store).unwrap();
		assert!(book.round(&reading(false), &RoundTrips::new(), at(20)).is_none());
		let ended = book.round(&reading(true), &RoundTrips::new(), at(61)).unwrap();
		assert!(ended.above >= left.version && ended.version > left.version);
		let minute = &ended.rows[0].minute;
		assert_eq!((minute.at, minute.beats), (at(0).as_millisecond(), 2));
		assert_eq!(minute.leaving, Some(Reason::Upgrade));
		assert_eq!(minute.down, BTreeMap::from([("geo".into(), 1)]));
	}

	#[tokio::test]
	async fn history_reads_the_file_and_the_window_together() {
		let store = shared(Store::memory().unwrap());
		let book = Book::open("rdu".into(), store).unwrap();
		for second in (0..180).step_by(3) {
			book.round(&reading(true), &RoundTrips::new(), at(second));
		}
		// Two minutes written, then one more held in memory alone.
		book.write(at(120)).await.unwrap();
		book.round(&reading(true), &RoundTrips::new(), at(181));
		let tyo = Batch {
			node: "tyo".into(),
			above: 0,
			version: 4,
			rows: vec![Row { version: 4, minute: Minute { beats: 7, ..ended(0) } }],
		};
		assert!(book.merge(tyo));

		let asked = answer::Asked::new(3600, 3600).unwrap();
		let history = book.history("rdu".into(), asked, vec![], at(300)).await.unwrap();
		let slot = &history.nodes["rdu"][0];
		// Minutes 0 to 2 held, and minute 3, due by now, never ended.
		assert_eq!((slot.beats, slot.due, slot.missing), (Some(3 * 20), Some(4 * 20), 1));
		assert_eq!(history.nodes["tyo"][0].beats, Some(7));
	}

	fn ended(minute: i64) -> Minute {
		Minute {
			at: at(minute * 60).as_millisecond(),
			beats: 20,
			down: BTreeMap::new(),
			held: 0,
			round_trip: RoundTrips::new(),
			leaving: None,
		}
	}
}
