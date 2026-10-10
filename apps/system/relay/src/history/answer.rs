//! `/history`: every node over a span ending now, cut into slots, each slot read from the finest
//! tier that still holds it. The tiers hold whole units of the one above, never a unit split
//! between two, so a slot sums whatever it holds of each. See spec/architecture/relay.md, "Each
//! node's minutes, kept for a year".

use super::fold::{Fold, minutes_between};
use super::outcomes::{Day, Outcomes, Run};
use super::{DAY, DAYS_KEPT, HOUR, HOURS_KEPT, MINUTE, MINUTES_KEPT, Minute, ROUNDS, floor};
use crate::window::milliseconds;
use jiff::Timestamp;
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet};

/// The most slots one answer holds.
pub const MOST: u64 = 1000;

/// A span and a slot that can be answered, in milliseconds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Asked {
	span: i64,
	slot: i64,
}

impl Asked {
	/// `span` and `slot` in seconds, or none where they cannot be answered: a span of whole slots,
	/// at most `MOST` of them and no longer than days are kept, and a slot of whole units of the
	/// coarsest tier the span reaches -- minutes within two days, hours within 30, days beyond.
	pub fn new(span: u64, slot: u64) -> Option<Self> {
		if slot == 0 || span == 0 || !span.is_multiple_of(slot) || span / slot > MOST {
			return None;
		}
		let span = i64::try_from(span).ok()?.checked_mul(1000)?;
		let slot = i64::try_from(slot).ok()?.checked_mul(1000)?;
		let unit = if span > milliseconds(HOURS_KEPT) {
			DAY
		} else if span > milliseconds(MINUTES_KEPT) {
			HOUR
		} else {
			MINUTE
		};
		(span <= milliseconds(DAYS_KEPT) && slot % unit == 0).then_some(Self { span, slot })
	}

	/// The first slot's start and the last's end at `now`: slots fall on whole multiples of their
	/// length, the last holding `now`.
	pub fn bounds(self, now: i64) -> (i64, i64) {
		let until = floor(now, self.slot) + self.slot;
		(until - self.span, until)
	}
}

/// What `/history` answers.
#[derive(Debug, Serialize)]
pub struct History {
	pub version: u32,
	/// The node whose relay answered.
	pub node: String,
	pub from: Timestamp,
	pub until: Timestamp,
	/// Each slot's length, in seconds.
	pub slot: i64,
	/// Each node's slots that hold anything, oldest first.
	pub nodes: BTreeMap<String, Vec<Slot>>,
}

/// One node over one slot.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Slot {
	pub at: Timestamp,
	/// The rounds that read host, of those due: one every three seconds of every minute from the
	/// first held of the node, a minute due once the minute after it has ended.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub beats: Option<u64>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub due: Option<u64>,
	/// The minutes due with no row: the node unheard.
	#[serde(skip_serializing_if = "is_zero")]
	pub missing: u32,
	/// Of those missing, the minutes after one in which it said it was leaving.
	#[serde(skip_serializing_if = "is_zero")]
	pub announced: u32,
	/// The minutes in which it said it was leaving.
	#[serde(skip_serializing_if = "is_zero")]
	pub leaving: u32,
	/// Each app down in it, and in how many rounds.
	#[serde(skip_serializing_if = "BTreeMap::is_empty")]
	pub down: BTreeMap<String, u32>,
	#[serde(skip_serializing_if = "BTreeMap::is_empty")]
	pub round_trip: BTreeMap<String, Spread>,
	#[serde(skip_serializing_if = "Outcomes::is_empty")]
	pub runs: Outcomes,
}

/// A neighbor's round trip over a slot, in seconds: the mean of its minutes, and the worst.
#[derive(Debug, Clone, Copy, PartialEq, Serialize)]
pub struct Spread {
	pub mean: f64,
	pub worst: f64,
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn is_zero(count: &u32) -> bool {
	*count == 0
}

/// One node's slot as it is gathered: what is held of it, its minutes held but not yet due, and
/// its runs.
#[derive(Debug, Clone, Default)]
struct Gathered {
	fold: Fold,
	early: u32,
	runs: Outcomes,
}

/// An answer being gathered, from whatever holds each slot.
pub struct Answering {
	slot: i64,
	from: i64,
	until: i64,
	/// The start of the last minute due.
	due: i64,
	nodes: BTreeMap<String, Vec<Gathered>>,
	/// Each node's units held in the span, by start and end, and whether each ends leaving.
	held: BTreeMap<String, Vec<(i64, i64, bool)>>,
	first: BTreeMap<String, i64>,
	/// Each node's last unit held before the span: its end, and whether it ends leaving.
	tails: BTreeMap<String, (i64, bool)>,
	days: Vec<Day>,
}

impl Answering {
	pub fn new(asked: Asked, now: i64) -> Self {
		let (from, until) = asked.bounds(now);
		let due = floor(now, MINUTE) - 2 * MINUTE;
		let (nodes, held, first, tails) =
			(BTreeMap::new(), BTreeMap::new(), BTreeMap::new(), BTreeMap::new());
		Self { slot: asked.slot, from, until, due, nodes, held, first, tails, days: Vec::new() }
	}

	pub fn span(&self) -> (i64, i64) {
		(self.from, self.until)
	}

	fn gathered(&mut self, node: &str, at: i64) -> Option<&mut Gathered> {
		if !(self.from..self.until).contains(&at) {
			return None;
		}
		let index = usize::try_from((at - self.from) / self.slot).ok()?;
		let count = usize::try_from((self.until - self.from) / self.slot).ok()?;
		let slots =
			self.nodes.entry(node.to_owned()).or_insert_with(|| vec![Gathered::default(); count]);
		slots.get_mut(index)
	}

	/// What a tier holds of `node` from `at` for `length`.
	pub fn held(&mut self, node: &str, at: i64, length: i64, fold: &Fold) {
		let early = length == MINUTE && at > self.due;
		if let Some(gathered) = self.gathered(node, at) {
			gathered.fold.add(fold);
			gathered.early += u32::from(early);
			let units = self.held.entry(node.to_owned()).or_default();
			units.push((at, at + length, fold.tail));
		}
	}

	pub fn minute(&mut self, node: &str, minute: &Minute) {
		self.held(node, minute.at, MINUTE, &Fold::minute(minute));
	}

	/// Each node's last unit before the span; see `store::tails`.
	pub fn tails(&mut self, tails: BTreeMap<String, (i64, bool)>) {
		self.tails = tails;
	}

	/// The minutes due between the units held, after one that ended leaving: the node away as it
	/// said, for whole units no tier holds a row of. A unit's own gaps its fold has counted.
	fn announce(&mut self) {
		let due = (self.due + MINUTE).min(self.until);
		let nodes: BTreeSet<String> = self.held.keys().chain(self.tails.keys()).cloned().collect();
		for node in nodes {
			let mut units = self.held.get(&node).cloned().unwrap_or_default();
			units.sort_unstable();
			let (mut from, mut leaving) = self.tails.get(&node).copied().unwrap_or((self.from, false));
			for (start, end, tail) in units.into_iter().chain([(due, due, false)]) {
				if leaving {
					self.away(&node, from.max(self.from), start.min(due));
				}
				(from, leaving) = (end, tail);
			}
		}
	}

	/// The minutes from `from` until `until` counted as announced, each in its slot.
	fn away(&mut self, node: &str, from: i64, until: i64) {
		let mut at = from;
		while at < until {
			let end = (floor(at - self.from, self.slot) + self.from + self.slot).min(until);
			if let Some(gathered) = self.gathered(node, at) {
				gathered.fold.announced += minutes_between(at, end);
			}
			at = end;
		}
	}

	/// Each node's earliest moment held: what is due of it begins there.
	pub fn first(&mut self, first: BTreeMap<String, i64>) {
		self.first = first;
	}

	pub fn days(&mut self, days: Vec<Day>) {
		self.days = days;
	}

	/// The runs, each in the slot its first row started in. A slot of whole days takes a day's
	/// count where the day was counted, and the mirror's rows where it was not; a finer one has
	/// only the rows.
	pub fn runs(mut self, runs: Vec<Run>) -> Self {
		let (mut counted, mut beyond) = (BTreeSet::new(), BTreeSet::new());
		if self.slot >= DAY {
			for day in std::mem::take(&mut self.days) {
				counted.insert((day.node.clone(), day.at));
				beyond.extend(day.beyond.iter().map(|run| (day.node.clone(), *run)));
				if let Some(gathered) = self.gathered(&day.node, day.at) {
					gathered.runs.add(day.outcomes);
				}
			}
		}
		for run in runs {
			let day = (run.node.clone(), floor(run.started, DAY));
			let carried = run.run.is_some_and(|id| beyond.contains(&(run.node.clone(), id)));
			if counted.contains(&day) || carried {
				continue;
			}
			if let Some(gathered) = self.gathered(&run.node, run.started) {
				gathered.runs.count(run.outcome);
			}
		}
		self
	}

	pub fn answered(mut self, node: String) -> History {
		self.announce();
		let mut nodes = BTreeMap::new();
		for (name, gathered) in &self.nodes {
			// A minute held in memory alone may be earlier than any in the file.
			let held = self.held.get(name).and_then(|units| units.iter().map(|unit| unit.0).min());
			let first = self.first.get(name).copied().into_iter().chain(held).min();
			let slots: Vec<Slot> = gathered
				.iter()
				.enumerate()
				.filter_map(|(index, gathered)| {
					let at = self.from + i64::try_from(index).ok()? * self.slot;
					self.slot_of(at, first, gathered)
				})
				.collect();
			if !slots.is_empty() {
				nodes.insert(name.clone(), slots);
			}
		}
		let time = |at| Timestamp::from_millisecond(at).unwrap_or(Timestamp::UNIX_EPOCH);
		History {
			version: crate::relay::VERSION,
			node,
			from: time(self.from),
			until: time(self.until),
			slot: self.slot / 1000,
			nodes,
		}
	}

	/// The slot from `at`, or none where it holds nothing. Every minute in it from `first` through
	/// the last due is due, and so is each minute held that is not due yet.
	fn slot_of(&self, at: i64, first: Option<i64>, gathered: &Gathered) -> Option<Slot> {
		let elapsed = first.map_or(0, |first| {
			let (from, until) = (at.max(first), (at + self.slot).min(self.due + MINUTE));
			u32::try_from((until - from).max(0) / MINUTE).unwrap_or(u32::MAX)
		});
		let minutes = elapsed + gathered.early;
		let Gathered { fold, runs, .. } = gathered;
		if minutes == 0 && runs.is_empty() {
			return None;
		}
		let round_trip = fold
			.round_trip
			.iter()
			.map(|(peer, trip)| (peer.clone(), Spread { mean: trip.mean, worst: trip.worst }));
		Some(Slot {
			at: Timestamp::from_millisecond(at).ok()?,
			beats: (minutes > 0).then_some(fold.beats),
			due: (minutes > 0).then_some(u64::from(minutes) * u64::from(ROUNDS)),
			missing: minutes.saturating_sub(fold.minutes),
			announced: fold.announced,
			leaving: fold.leaving,
			down: fold.down.clone(),
			round_trip: round_trip.collect(),
			runs: *runs,
		})
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::history::outcomes::Outcome;
	use crate::presence::Reason;

	/// Midnight on 2026-10-09, in milliseconds.
	const DAWN: i64 = 1_791_504_000_000;

	fn minute(at: i64, leaving: bool) -> Minute {
		let leaving = leaving.then_some(Reason::Restart);
		let round_trip = BTreeMap::from([("rdu".into(), 0.15)]);
		let down = BTreeMap::from([("geo".into(), 2)]);
		Minute { at, beats: 20, down, held: 0, round_trip, leaving }
	}

	fn run(run: Option<u64>, started: i64, outcome: Outcome) -> Run {
		Run { node: "tyo".into(), run, started, last: started, outcome }
	}

	#[test]
	fn a_span_and_slot_are_answered_only_where_the_tiers_can_hold_them() {
		assert!(Asked::new(3600, 60).is_some());
		assert!(Asked::new(2 * 86_400, 180).is_some());
		assert!(Asked::new(7 * 86_400, 3600).is_some());
		assert!(Asked::new(365 * 86_400, 86_400).is_some());
		for (span, slot) in [
			(0, 60),
			(3600, 0),
			// Not whole slots, a slot finer than a minute, and more than a thousand slots.
			(3600, 7 * 60),
			(60, 30),
			(86_400, 60),
			// Past two days in minutes, past 30 in hours, and past what is kept at all.
			(3 * 86_400, 1800),
			(40 * 86_400, 3 * 3600),
			(401 * 86_400, 86_400),
		] {
			assert!(Asked::new(span, slot).is_none(), "{span} {slot}");
		}
	}

	#[test]
	fn each_slot_is_read_from_whatever_tier_holds_it_and_counts_what_is_missing() {
		let now = DAWN + 10 * DAY + 30 * MINUTE + 10_000;
		let mut answering = Answering::new(Asked::new(3 * 86_400, 86_400).unwrap(), now);
		assert_eq!(answering.span(), (DAWN + 8 * DAY, DAWN + 11 * DAY));
		// Day 8 is held as an hour, which ends saying it is leaving; nothing more until day 10.
		let hour = Fold { minutes: 60, beats: 1200, leaving: 1, tail: true, ..Fold::default() };
		answering.held("tyo", DAWN + 8 * DAY, HOUR, &hour);
		// Day 10 as minutes: leaving said at minute 4, minute 5 missing, minute 29 not due yet.
		for at in (0..30).filter(|at| *at != 5) {
			answering.minute("tyo", &minute(DAWN + 10 * DAY + at * MINUTE, at == 4));
		}
		answering.first(BTreeMap::from([("tyo".into(), DAWN + 8 * DAY)]));
		let history = answering.runs(vec![]).answered("rdu".into());

		let slots = &history.nodes["tyo"];
		// Beats, due, missing, announced and leaving.
		type Read = (Option<u64>, Option<u64>, u32, u32, u32);
		let read: Vec<Read> = slots
			.iter()
			.map(|slot| (slot.beats, slot.due, slot.missing, slot.announced, slot.leaving))
			.collect();
		assert_eq!(
			read,
			[
				(Some(1200), Some(1440 * 20), 1380, 1380, 1),
				(Some(0), Some(1440 * 20), 1440, 1440, 0),
				(Some(29 * 20), Some(30 * 20), 1, 1, 1),
			]
		);
		assert_eq!(slots[2].down, BTreeMap::from([("geo".into(), 58)]));
		assert_eq!(slots[2].round_trip["rdu"], Spread { mean: 0.15, worst: 0.15 });

		let written = serde_json::to_value(&history).unwrap();
		assert_eq!(written["slot"], 86_400);
		assert_eq!(written["from"], "2026-10-17T00:00:00Z");
		assert!(written["nodes"]["tyo"][0].get("runs").is_none());
	}

	#[test]
	fn a_gap_not_announced_is_missing_alone_and_nothing_is_due_before_the_first_minute() {
		let now = DAWN + 2 * HOUR + 10_000;
		let mut answering = Answering::new(Asked::new(3 * 3600, 3600).unwrap(), now);
		answering.minute("tyo", &minute(DAWN + 30 * MINUTE, false));
		answering.minute("tyo", &minute(DAWN + 40 * MINUTE, false));
		answering.first(BTreeMap::from([("tyo".into(), DAWN + 30 * MINUTE)]));
		let history = answering.runs(vec![]).answered("rdu".into());
		let read: Vec<(u32, u32, Option<u64>)> =
			history.nodes["tyo"].iter().map(|slot| (slot.missing, slot.announced, slot.due)).collect();
		// Nothing is due before the first minute; of the hour before this one, every minute is due
		// but its last, and this one holds none due yet, so it is absent.
		assert_eq!(read, [(28, 0, Some(30 * 20)), (59, 0, Some(59 * 20))]);
	}

	#[test]
	fn whole_days_take_a_days_count_and_finer_slots_the_mirrors_rows() {
		let now = DAWN + 40 * DAY;
		let day = Day {
			node: "tyo".into(),
			at: DAWN,
			outcomes: Outcomes { succeeded: 2, ..Outcomes::default() },
			beyond: vec![7],
		};
		let runs = || {
			vec![
				// Counted in the day already, and run 7 begun in it and going on into the next.
				run(Some(8), DAWN + 5 * HOUR, Outcome::Failed),
				run(Some(7), DAWN + DAY + MINUTE, Outcome::Succeeded),
				run(None, DAWN + 2 * DAY, Outcome::PartlyFailed),
			]
		};
		let mut answering = Answering::new(Asked::new(41 * 86_400, 86_400).unwrap(), now);
		answering.days(vec![day.clone()]);
		let history = answering.runs(runs()).answered("rdu".into());
		let counted: Vec<(Timestamp, Outcomes)> =
			history.nodes["tyo"].iter().map(|slot| (slot.at, slot.runs)).collect();
		let at = |at| Timestamp::from_millisecond(at).unwrap();
		let partly = Outcomes { partly_failed: 1, ..Outcomes::default() };
		assert_eq!(counted, [(at(DAWN), day.outcomes), (at(DAWN + 2 * DAY), partly)]);

		// By the hour, the day's count is left aside and its rows are read.
		let now = DAWN + 2 * DAY + HOUR;
		let mut answering = Answering::new(Asked::new(3 * 86_400, 3600).unwrap(), now);
		answering.days(vec![day]);
		let history = answering.runs(runs()).answered("rdu".into());
		let runs: u32 =
			history.nodes["tyo"].iter().map(|slot| slot.runs.failed + slot.runs.succeeded).sum();
		assert_eq!(runs, 2);
	}
}
