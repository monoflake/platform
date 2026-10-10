//! An hour or a day of one node, folded from the tier under it as that tier is dropped. A fold is
//! the same wherever it is made, from the same minutes. See spec/architecture/relay.md, "Each
//! node's minutes, kept for a year".

use super::tally::rounded;
use super::{MINUTE, Minute};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// What a fold holds. The minutes missing are its length less `minutes`, read where it is
/// answered, since what is due of a node begins at the first minute held of it.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct Fold {
	/// The minutes of it held, each a row of its node's.
	pub minutes: u32,
	pub beats: u64,
	/// Each app down in it, and in how many rounds.
	#[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
	pub down: BTreeMap<String, u32>,
	/// The minutes in which the node said it was leaving.
	#[serde(default, skip_serializing_if = "is_zero")]
	pub leaving: u32,
	/// The minutes missing after one that said it was leaving: the node away as it said.
	#[serde(default, skip_serializing_if = "is_zero")]
	pub announced: u32,
	/// Whether the last minute held, here or before it, said the node was leaving: a gap after it
	/// is announced.
	#[serde(default, skip_serializing_if = "std::ops::Not::not")]
	pub tail: bool,
	#[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
	pub round_trip: BTreeMap<String, Trip>,
}

/// One neighbor's round trip over the minutes it was timed in: the mean of those minutes, and the
/// worst of them.
#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct Trip {
	pub mean: f64,
	pub worst: f64,
	pub minutes: u32,
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn is_zero(count: &u32) -> bool {
	*count == 0
}

/// The whole minutes from `from` until `until`, none where `until` is not later.
pub fn minutes_between(from: i64, until: i64) -> u32 {
	u32::try_from((until - from).max(0) / MINUTE).unwrap_or(u32::MAX)
}

impl Fold {
	/// One minute as a fold of one.
	pub fn minute(minute: &Minute) -> Self {
		let round_trip = minute
			.round_trip
			.iter()
			.map(|(peer, &seconds)| (peer.clone(), Trip { mean: seconds, worst: seconds, minutes: 1 }));
		Self {
			minutes: 1,
			beats: u64::from(minute.beats),
			down: minute.down.clone(),
			leaving: u32::from(minute.leaving.is_some()),
			announced: 0,
			tail: minute.leaving.is_some(),
			round_trip: round_trip.collect(),
		}
	}

	/// The unit from `at` until `until`, from what is held of it in order, each by its start and
	/// its end; `leaving` is whether the last minute held before it said the node was leaving.
	pub fn of<'a>(
		at: i64,
		until: i64,
		leaving: bool,
		held: impl IntoIterator<Item = (i64, i64, &'a Fold)>,
	) -> Self {
		let mut fold = Self { tail: leaving, ..Self::default() };
		let mut from = at;
		for (start, end, part) in held {
			fold.gap(from, start);
			fold.add(part);
			fold.tail = part.tail;
			from = end;
		}
		fold.gap(from, until);
		fold
	}

	/// The minutes from `from` until `until` missing, announced where the minute before said so.
	fn gap(&mut self, from: i64, until: i64) {
		if self.tail {
			self.announced += minutes_between(from, until);
		}
	}

	/// The sums of both; `tail` is the caller's, which knows which comes last.
	pub fn add(&mut self, fold: &Fold) {
		self.minutes += fold.minutes;
		self.beats += fold.beats;
		for (app, rounds) in &fold.down {
			*self.down.entry(app.clone()).or_default() += rounds;
		}
		self.leaving += fold.leaving;
		self.announced += fold.announced;
		for (peer, &trip) in &fold.round_trip {
			self
				.round_trip
				.entry(peer.clone())
				.and_modify(|held| *held = held.with(trip))
				.or_insert(trip);
		}
	}
}

impl Trip {
	/// The two together, the mean weighted by the minutes each was timed in.
	fn with(self, other: Self) -> Self {
		let minutes = self.minutes + other.minutes;
		let sum = self.mean * f64::from(self.minutes) + other.mean * f64::from(other.minutes);
		Self { mean: rounded(sum / f64::from(minutes)), worst: self.worst.max(other.worst), minutes }
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::presence::Reason;

	fn minute(at: i64, beats: u32, down: &[&str], trip: Option<f64>, leaving: bool) -> Fold {
		Fold::minute(&Minute {
			at,
			beats,
			down: down.iter().map(|app| ((*app).to_owned(), 2)).collect(),
			held: 0,
			round_trip: trip.map(|seconds| ("tyo".to_owned(), seconds)).into_iter().collect(),
			leaving: leaving.then_some(Reason::Restart),
		})
	}

	fn hour(leaving: bool, minutes: &[(i64, Fold)]) -> Fold {
		let held = minutes.iter().map(|(at, fold)| (at * MINUTE, (at + 1) * MINUTE, fold));
		Fold::of(0, 60 * MINUTE, leaving, held)
	}

	#[test]
	fn minutes_fold_into_sums_counts_and_a_mean_and_worst_round_trip() {
		let hour = hour(
			false,
			&[
				(0, minute(0, 20, &["geo"], Some(0.1), false)),
				(1, minute(1, 18, &["geo", "apt"], Some(0.3), false)),
				(59, minute(59, 3, &[], None, false)),
			],
		);
		assert_eq!(hour.minutes, 3);
		assert_eq!(hour.beats, 41);
		assert_eq!(hour.down, BTreeMap::from([("apt".into(), 2), ("geo".into(), 4)]));
		assert_eq!(hour.round_trip["tyo"], Trip { mean: 0.2, worst: 0.3, minutes: 2 });
		// Its gap of 57 minutes followed no word of leaving.
		assert_eq!((hour.leaving, hour.announced, hour.tail), (0, 0, false));

		// Folded again into a day, beside an hour of one minute timed at 0.5.
		let other = self::hour(false, &[(0, minute(0, 20, &[], Some(0.5), false))]);
		let day = Fold::of(
			0,
			24 * 60 * MINUTE,
			false,
			[(0, 60 * MINUTE, &hour), (60 * MINUTE, 120 * MINUTE, &other)],
		);
		assert_eq!((day.minutes, day.beats), (4, 61));
		assert_eq!(day.round_trip["tyo"], Trip { mean: 0.3, worst: 0.5, minutes: 3 });
	}

	#[test]
	fn a_gap_after_a_minute_that_said_it_was_leaving_is_announced_and_carried_on() {
		// Leaving said at minute 10, back at 13; leaving again at 58, and still away at the end.
		let hour = hour(
			false,
			&[
				(9, minute(9, 20, &[], None, false)),
				(10, minute(10, 4, &[], None, true)),
				(13, minute(13, 15, &[], None, false)),
				(58, minute(58, 5, &[], None, true)),
			],
		);
		assert_eq!((hour.leaving, hour.announced, hour.tail), (2, 2 + 1, true));
		// The next hour's gap before its first minute follows on from this one's word.
		let next = self::hour(hour.tail, &[(4, minute(4, 20, &[], None, false))]);
		assert_eq!((next.announced, next.tail), (4, false));
		let unannounced = self::hour(false, &[(4, minute(4, 20, &[], None, false))]);
		assert_eq!(unannounced.announced, 0);
	}
}
