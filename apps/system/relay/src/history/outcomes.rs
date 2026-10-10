//! How each run went on each node, from the mirror's rows within 30 days and from a count a node
//! and a day beyond them, folded as a day's first row is dropped. A run on a node is its rows of
//! one CI run, each app at its latest, or an action no run started -- by the panel, an upload or
//! keeper -- grouped by its source, its app and the minute it started, as the console groups them.
//! A row skipped says nothing of how it went. A run is placed by its first row's start, and one
//! going on past its day is named in the day's count, so the next day, no longer holding that first
//! row, does not count it again. See spec/architecture/relay.md, "Each node's minutes, kept for a
//! year".

use super::{DAY, DAYS_KEPT, MINUTE, floor};
use crate::host::Event;
use crate::runs::{StoreError, started};
use crate::window::milliseconds;
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Outcome {
	Succeeded,
	Failed,
	Running,
	/// Some of its apps succeeded on the node and some failed.
	PartlyFailed,
}

/// Runs by how they went.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Outcomes {
	#[serde(default, skip_serializing_if = "is_zero")]
	pub succeeded: u32,
	#[serde(default, skip_serializing_if = "is_zero")]
	pub failed: u32,
	#[serde(default, skip_serializing_if = "is_zero")]
	pub running: u32,
	#[serde(default, skip_serializing_if = "is_zero")]
	pub partly_failed: u32,
}

#[allow(clippy::trivially_copy_pass_by_ref)]
fn is_zero(count: &u32) -> bool {
	*count == 0
}

impl Outcomes {
	pub fn count(&mut self, outcome: Outcome) {
		*match outcome {
			Outcome::Succeeded => &mut self.succeeded,
			Outcome::Failed => &mut self.failed,
			Outcome::Running => &mut self.running,
			Outcome::PartlyFailed => &mut self.partly_failed,
		} += 1;
	}

	pub fn add(&mut self, other: Self) {
		self.succeeded += other.succeeded;
		self.failed += other.failed;
		self.running += other.running;
		self.partly_failed += other.partly_failed;
	}

	pub fn is_empty(&self) -> bool {
		*self == Self::default()
	}
}

/// A run on a node: the node, the CI run or none for an action apart from one, when its first and
/// last rows there started, and how it went.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Run {
	pub node: String,
	pub run: Option<u64>,
	pub started: i64,
	pub last: i64,
	pub outcome: Outcome,
}

/// One node's runs of one day, counted, and the runs among them that went on past it.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Day {
	pub node: String,
	pub at: i64,
	pub outcomes: Outcomes,
	pub beyond: Vec<u64>,
}

/// What rows are grouped by on a node: a CI run, or an action's source, app and minute.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
enum Group<'a> {
	Run(u64),
	Apart(&'a str, &'a str, i64),
}

/// Each run on each node among `rows`; a run whose rows were all skipped is none.
pub fn runs<'a>(rows: impl IntoIterator<Item = (&'a str, &'a Event)>) -> Vec<Run> {
	// By node and group: the first and last start, and each app's latest row by id.
	type Gathered<'a> = (i64, i64, BTreeMap<&'a str, &'a Event>);
	let mut grouped: BTreeMap<(&str, Group), Gathered> = BTreeMap::new();
	for (node, event) in rows {
		let Some(start) = started(event) else { continue };
		let group = match (event.source.kind.as_str(), event.source.run) {
			("run", Some(run)) => Group::Run(run),
			(kind, _) => Group::Apart(kind, &event.app, floor(start, MINUTE)),
		};
		let (first, last, apps) =
			grouped.entry((node, group)).or_insert((start, start, BTreeMap::new()));
		*first = (*first).min(start);
		*last = (*last).max(start);
		if apps.get(event.app.as_str()).is_none_or(|held| held.id < event.id) {
			apps.insert(&event.app, event);
		}
	}
	grouped
		.into_iter()
		.filter_map(|((node, group), (started, last, apps))| {
			let outcome = outcome(apps.values().map(|event| event.outcome.as_str()))?;
			let run = match group {
				Group::Run(run) => Some(run),
				Group::Apart(..) => None,
			};
			Some(Run { node: node.to_owned(), run, started, last, outcome })
		})
		.collect()
}

fn outcome<'a>(outcomes: impl Iterator<Item = &'a str>) -> Option<Outcome> {
	let (mut succeeded, mut failed, mut running) = (false, false, false);
	for outcome in outcomes {
		match outcome {
			"succeeded" => succeeded = true,
			"failed" => failed = true,
			"running" => running = true,
			_ => {}
		}
	}
	Some(match (running, succeeded, failed) {
		(true, _, _) => Outcome::Running,
		(false, true, true) => Outcome::PartlyFailed,
		(false, true, false) => Outcome::Succeeded,
		(false, false, true) => Outcome::Failed,
		(false, false, false) => return None,
	})
}

/// Counts each node's runs of every day with a row about to be dropped, below `cutoff`, and not
/// counted yet: every row of that day is still held, since none of it has gone before. Days past
/// keeping go.
pub fn fold(connection: &Connection, cutoff: i64, now: i64) -> Result<(), StoreError> {
	let mut days = connection.prepare_cached(
		"SELECT DISTINCT node, started - started % ?2 FROM runs WHERE started < ?1
		AND NOT EXISTS (SELECT 1 FROM run_days
			WHERE run_days.node = runs.node AND run_days.at = runs.started - runs.started % ?2)",
	)?;
	let due: Vec<(String, i64)> = days
		.query_map(params![cutoff, DAY], |row| Ok((row.get(0)?, row.get(1)?)))?
		.collect::<rusqlite::Result<_>>()?;
	let mut select = connection
		.prepare_cached("SELECT event FROM runs WHERE node = ?1 AND started >= ?2 AND started < ?3")?;
	let mut insert = connection.prepare_cached(
		"INSERT OR IGNORE INTO run_days (node, at, outcomes, beyond) VALUES (?1, ?2, ?3, ?4)",
	)?;
	for (node, day) in due {
		// A run's rows a day either side, so one begun the day before is not counted as begun here.
		let rows =
			select.query_map(params![node, day - DAY, day + 2 * DAY], |row| row.get::<_, String>(0))?;
		let mut events = Vec::new();
		for row in rows {
			events.push(serde_json::from_str::<Event>(&row?)?);
		}
		let counted: Vec<u64> = read(connection, Some(&node), day - 2 * DAY, day)?
			.into_iter()
			.flat_map(|earlier| earlier.beyond)
			.collect();
		let (mut outcomes, mut beyond) = (Outcomes::default(), Vec::new());
		let runs = runs(events.iter().map(|event| (node.as_str(), event)));
		for run in runs {
			if floor(run.started, DAY) != day || run.run.is_some_and(|id| counted.contains(&id)) {
				continue;
			}
			outcomes.count(run.outcome);
			if let Some(id) = run.run.filter(|_| run.last >= day + DAY) {
				beyond.push(id);
			}
		}
		let (outcomes, beyond) = (serde_json::to_string(&outcomes)?, serde_json::to_string(&beyond)?);
		insert.execute(params![node, day, outcomes, beyond])?;
	}
	let past = floor(now - milliseconds(DAYS_KEPT), DAY);
	connection.execute("DELETE FROM run_days WHERE at < ?1", params![past])?;
	Ok(())
}

/// Every node's counted days from `from` until `until`, or one node's.
pub fn read(
	connection: &Connection,
	node: Option<&str>,
	from: i64,
	until: i64,
) -> Result<Vec<Day>, StoreError> {
	let mut select = connection.prepare_cached(
		"SELECT node, at, outcomes, beyond FROM run_days
		WHERE at >= ?1 AND at < ?2 AND (?3 IS NULL OR node = ?3) ORDER BY node, at",
	)?;
	let rows = select.query_map(params![from, until, node], |row| {
		Ok((row.get(0)?, row.get(1)?, row.get(2)?, row.get(3)?))
	})?;
	let mut days = Vec::new();
	for row in rows {
		let (node, at, outcomes, beyond): (String, i64, String, String) = row?;
		let (outcomes, beyond) = (serde_json::from_str(&outcomes)?, serde_json::from_str(&beyond)?);
		days.push(Day { node, at, outcomes, beyond });
	}
	Ok(days)
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::host::Source;
	use crate::runs::{Row, Store};
	use jiff::Timestamp;

	fn event(id: i64, run: u64, app: &str, outcome: &str, started: i64) -> Event {
		Event {
			id,
			app: app.into(),
			action: "deploy".into(),
			source: Source { kind: "run".into(), run: Some(run), commit: None },
			image: None,
			outcome: outcome.into(),
			stage: None,
			detail: None,
			started_at: Timestamp::from_millisecond(started).unwrap().to_string(),
			finished_at: None,
		}
	}

	/// Midnight on 2026-10-09, in milliseconds.
	const DAWN: i64 = 1_791_504_000_000;

	#[test]
	fn a_run_on_a_node_is_its_apps_latest_rows_skips_saying_nothing() {
		let rows = [
			("rdu", event(1, 7, "geo", "failed", DAWN)),
			("rdu", event(2, 7, "geo", "succeeded", DAWN + 5)),
			("rdu", event(3, 7, "apt", "failed", DAWN + 9)),
			("tyo", event(4, 7, "geo", "succeeded", DAWN + 2)),
			("tyo", event(5, 8, "geo", "skipped", DAWN + 2)),
			("tyo", event(6, 9, "apt", "running", DAWN + 3)),
			("tyo", event(7, 9, "geo", "failed", DAWN + 1)),
		];
		// The panel's: a restart failed then retried in the same minute is one; the next minute's,
		// and another app's, are their own.
		let panel = |id, app: &str, outcome, started| {
			let mut panel = event(id, 0, app, outcome, started);
			panel.source = Source { kind: "panel".into(), run: None, commit: None };
			panel
		};
		let apart = [
			panel(8, "geo", "failed", DAWN),
			panel(9, "geo", "succeeded", DAWN + 30_000),
			panel(10, "geo", "failed", DAWN + 60_000),
			panel(11, "apt", "succeeded", DAWN + 30_000),
		];
		let rows = rows.iter().map(|(node, event)| (*node, event));
		let runs = runs(rows.chain(apart.iter().map(|event| ("rdu", event))));
		let read: Vec<(&str, Option<u64>, i64, Outcome)> =
			runs.iter().map(|run| (run.node.as_str(), run.run, run.started, run.outcome)).collect();
		assert_eq!(
			read,
			[
				("rdu", Some(7), DAWN, Outcome::PartlyFailed),
				("rdu", None, DAWN + 30_000, Outcome::Succeeded),
				("rdu", None, DAWN, Outcome::Succeeded),
				("rdu", None, DAWN + 60_000, Outcome::Failed),
				("tyo", Some(7), DAWN + 2, Outcome::Succeeded),
				("tyo", Some(9), DAWN + 1, Outcome::Running),
			]
		);
	}

	#[test]
	fn a_days_runs_are_counted_before_its_rows_go_and_once() {
		let mut store = Store::memory().unwrap();
		// Run 7 begins the day before and ends on it; run 8 is the day's own, on two apps.
		let rows = [
			event(1, 7, "geo", "succeeded", DAWN - 60_000),
			event(2, 7, "apt", "succeeded", DAWN + 60_000),
			event(3, 8, "geo", "succeeded", DAWN + 3_600_000),
			event(4, 8, "apt", "failed", DAWN + 3_600_000),
			event(5, 9, "geo", "failed", DAWN + 2 * DAY),
		];
		let rows: Vec<(String, Row)> =
			rows.into_iter().map(|event| ("tyo".into(), Row { version: 1, event })).collect();
		let kept = Timestamp::from_millisecond(DAWN).unwrap() + crate::runs::KEPT;
		store.keep(&rows, kept).unwrap();
		// The cutoff is at the day's start: nothing of it has gone, and the day before is counted.
		let counted = read(store.connection(), None, DAWN - DAY, DAWN + 3 * DAY).unwrap();
		let before = Outcomes { succeeded: 1, ..Outcomes::default() };
		let day = |at, outcomes, beyond| Day { node: "tyo".into(), at, outcomes, beyond };
		assert_eq!(counted, [day(DAWN - DAY, before, vec![7])]);

		let later = kept + jiff::SignedDuration::from_hours(2);
		store.keep(&[], later).unwrap();
		// Run 7's first row is gone, and it is still not counted again.
		let counted = read(store.connection(), Some("tyo"), DAWN, DAWN + 3 * DAY).unwrap();
		let partly = Outcomes { partly_failed: 1, ..Outcomes::default() };
		assert_eq!(counted, [day(DAWN, partly, vec![])]);
		// Counted once, though rows of the day stay a while yet.
		store.keep(&[], later + jiff::SignedDuration::from_hours(1)).unwrap();
		assert_eq!(read(store.connection(), None, DAWN, DAWN + DAY).unwrap().len(), 1);
	}
}
