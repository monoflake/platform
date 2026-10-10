//! This node's minute as its rounds make it: each round of host adds to it, and it is a row once
//! the minute ends. See spec/architecture/relay.md, "Each node's minutes, kept for a year".

use super::{Minute, ROUNDS, minute_of};
use crate::host::App;
use crate::own::RoundTrips;
use crate::presence::Reason;
use jiff::Timestamp;
use std::collections::BTreeMap;

#[derive(Debug, Default)]
pub struct Tally {
	counting: Option<Counting>,
	/// Once the relay has said it is leaving: a round still under way is not counted.
	left: bool,
}

#[derive(Debug)]
struct Counting {
	at: i64,
	beats: u32,
	/// Each app's rounds down.
	down: BTreeMap<String, u32>,
	held: u32,
	/// Each neighbor's round trips this minute, summed, and how many.
	timed: BTreeMap<String, (f64, u32)>,
}

impl Tally {
	/// One round at `now`: whether it read host, the apps it read, and the round trips as they
	/// stand. The minute before is given back, ended, once a round falls in another.
	pub fn round(
		&mut self,
		read: bool,
		apps: Option<&[App]>,
		round_trips: &RoundTrips,
		now: Timestamp,
	) -> Option<Minute> {
		if self.left {
			return None;
		}
		let at = minute_of(now);
		let ended = match self.counting.take() {
			Some(counting) if counting.at != at => Some(counting.ended(None)),
			still => {
				self.counting = still;
				None
			}
		};
		self.counting.get_or_insert_with(|| Counting::new(at)).add(read, apps, round_trips);
		ended
	}

	/// The minute it is, ended now and carrying why the relay is leaving, after one a round has not
	/// yet ended; no round counts after it.
	pub fn leave(&mut self, reason: Reason, now: Timestamp) -> Vec<Minute> {
		self.left = true;
		let at = minute_of(now);
		let mut ended = Vec::with_capacity(2);
		let counting = match self.counting.take() {
			Some(counting) if counting.at == at => counting,
			earlier => {
				ended.extend(earlier.map(|counting| counting.ended(None)));
				Counting::new(at)
			}
		};
		ended.push(counting.ended(Some(reason)));
		ended
	}
}

impl Counting {
	fn new(at: i64) -> Self {
		Self { at, beats: 0, down: BTreeMap::new(), held: 0, timed: BTreeMap::new() }
	}

	/// An app is down in a round that read it neither running nor held.
	fn add(&mut self, read: bool, apps: Option<&[App]>, round_trips: &RoundTrips) {
		self.beats += u32::from(read);
		if let Some(apps) = apps {
			for app in apps.iter().filter(|app| !app.running && !app.held) {
				*self.down.entry(app.name.clone()).or_default() += 1;
			}
			let held = apps.iter().filter(|app| app.held).count();
			self.held = self.held.max(u32::try_from(held).unwrap_or(u32::MAX));
		}
		for (peer, round_trip) in round_trips {
			let (sum, count) = self.timed.entry(peer.clone()).or_default();
			*sum += round_trip;
			*count += 1;
		}
	}

	fn ended(self, leaving: Option<Reason>) -> Minute {
		let round_trip =
			self.timed.into_iter().map(|(peer, (sum, count))| (peer, rounded(sum / f64::from(count))));
		Minute {
			at: self.at,
			// A round late on the one before can put a twenty-first in a minute.
			beats: self.beats.min(ROUNDS),
			down: self.down.into_iter().map(|(app, rounds)| (app, rounds.min(ROUNDS))).collect(),
			held: self.held,
			round_trip: round_trip.collect(),
			leaving,
		}
	}
}

/// To a tenth of a millisecond, as a snapshot's round trip is.
pub fn rounded(seconds: f64) -> f64 {
	(seconds * 10_000.0).round() / 10_000.0
}

#[cfg(test)]
mod tests {
	use super::*;

	/// A moment `seconds` into a minute on 2026-10-09.
	fn at(seconds: i64) -> Timestamp {
		Timestamp::from_second(1_791_499_980 + seconds).unwrap()
	}

	fn app(name: &str, running: bool, held: bool) -> App {
		App {
			name: name.into(),
			image: format!("{name}:1"),
			deployed_at: "2026-10-05T08:00:00Z".into(),
			running,
			held,
			rollout: "replace".into(),
			label: None,
		}
	}

	#[test]
	fn a_minute_is_written_from_its_rounds_once_a_round_falls_in_the_next() {
		assert_eq!(at(0).as_millisecond() % 60_000, 0);
		let mut tally = Tally::default();
		let up = [app("geo", true, false), app("apt", false, true)];
		let down = [app("geo", false, false), app("apt", false, true)];
		let trips = |seconds: f64| RoundTrips::from([("tyo".into(), seconds)]);
		assert!(tally.round(true, Some(&up), &trips(0.15), at(0)).is_none());
		assert!(tally.round(true, Some(&down), &trips(0.17), at(3)).is_none());
		// Host not read: no beat, and no apps to say anything of.
		assert!(tally.round(false, None, &RoundTrips::new(), at(6)).is_none());

		let minute = tally.round(true, Some(&up), &trips(0.2), at(60)).unwrap();
		assert_eq!(minute.at, at(0).as_millisecond());
		assert_eq!(minute.beats, 2);
		assert_eq!(minute.down, BTreeMap::from([("geo".into(), 1)]));
		assert_eq!(minute.held, 1);
		assert_eq!(minute.round_trip, RoundTrips::from([("tyo".into(), 0.16)]));
		assert_eq!(minute.leaving, None);

		let written = serde_json::to_value(&minute).unwrap();
		assert_eq!(
			written,
			serde_json::json!({ "at": at(0).as_millisecond(), "beats": 2, "down": { "geo": 1 },
				"held": 1, "round_trip": { "tyo": 0.16 } })
		);
	}

	#[test]
	fn a_minute_holds_at_most_the_rounds_it_is_due() {
		let mut tally = Tally::default();
		for round in 0..25 {
			tally.round(true, Some(&[]), &RoundTrips::new(), at(round * 2));
		}
		let minute = tally.round(true, Some(&[]), &RoundTrips::new(), at(60)).unwrap();
		assert_eq!(minute.beats, ROUNDS);
		assert!(serde_json::to_value(&minute).unwrap().get("down").is_none());
	}

	#[test]
	fn leaving_ends_the_minute_it_is_said_in_and_the_one_before_it_unended() {
		let mut tally = Tally::default();
		tally.round(true, Some(&[]), &RoundTrips::new(), at(57));
		let minutes = tally.leave(Reason::Upgrade, at(61));
		let said: Vec<(i64, u32, Option<Reason>)> =
			minutes.iter().map(|minute| (minute.at, minute.beats, minute.leaving)).collect();
		let next = at(60).as_millisecond();
		assert_eq!(said, [(at(0).as_millisecond(), 1, None), (next, 0, Some(Reason::Upgrade))]);
		// A round under way as the relay stops counts for nothing.
		assert!(tally.round(true, Some(&[]), &RoundTrips::new(), at(130)).is_none());
	}
}
