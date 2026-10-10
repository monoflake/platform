//! The minutes and their folds in the relay's file, beside the runs: minutes for two days, hours
//! for 30 and days for 400, each tier folded into the one above as it is dropped. See
//! spec/architecture/relay.md, "Each node's minutes, kept for a year".

use super::fold::Fold;
use super::{DAY, DAYS_KEPT, HOUR, HOURS_KEPT, MINUTE, MINUTES_KEPT, Minute, Row, floor};
use crate::cluster::Versions;
use crate::runs::{StoreError, loaded, stored};
use crate::window::milliseconds;
use rusqlite::{Connection, Transaction, params};
use std::collections::{BTreeMap, BTreeSet};

pub fn ready(connection: &Connection) -> rusqlite::Result<()> {
	connection.execute_batch(
		"CREATE TABLE IF NOT EXISTS minutes (
			node TEXT NOT NULL,
			at INTEGER NOT NULL,
			version INTEGER NOT NULL,
			minute TEXT NOT NULL,
			PRIMARY KEY (node, at)
		) WITHOUT ROWID;
		CREATE INDEX IF NOT EXISTS minutes_version ON minutes (node, version);
		CREATE TABLE IF NOT EXISTS hours (
			node TEXT NOT NULL,
			at INTEGER NOT NULL,
			fold TEXT NOT NULL,
			PRIMARY KEY (node, at)
		) WITHOUT ROWID;
		CREATE TABLE IF NOT EXISTS days (
			node TEXT NOT NULL,
			at INTEGER NOT NULL,
			fold TEXT NOT NULL,
			PRIMARY KEY (node, at)
		) WITHOUT ROWID;
		CREATE TABLE IF NOT EXISTS run_days (
			node TEXT NOT NULL,
			at INTEGER NOT NULL,
			outcomes TEXT NOT NULL,
			beyond TEXT NOT NULL,
			PRIMARY KEY (node, at)
		) WITHOUT ROWID;",
	)
}

/// The oldest minute, hour and day kept at `now`: each tier is dropped a whole unit of the one
/// above at a time, so a unit is held in one tier, never split across two.
pub fn kept(now: i64) -> [i64; 3] {
	[
		floor(now - milliseconds(MINUTES_KEPT), HOUR),
		floor(now - milliseconds(HOURS_KEPT), DAY),
		floor(now - milliseconds(DAYS_KEPT), DAY),
	]
}

/// The newest version of the minutes written, by node.
pub fn held(connection: &Connection) -> Result<Versions, StoreError> {
	let mut select = connection.prepare("SELECT node, MAX(version) FROM minutes GROUP BY node")?;
	let rows = select.query_map([], |row| Ok((row.get(0)?, loaded(row.get(1)?))))?;
	Ok(rows.collect::<rusqlite::Result<_>>()?)
}

/// `node`'s minutes above `version`.
pub fn above(connection: &Connection, node: &str, version: u64) -> Result<Vec<Row>, StoreError> {
	let mut select = connection
		.prepare_cached("SELECT version, minute FROM minutes WHERE node = ?1 AND version > ?2")?;
	let rows =
		select.query_map(params![node, stored(version)], |row| Ok((row.get(0)?, row.get(1)?)))?;
	let mut above = Vec::new();
	for row in rows {
		let (version, minute): (i64, String) = row?;
		above.push(Row { version: loaded(version), minute: serde_json::from_str(&minute)? });
	}
	Ok(above)
}

/// `node`'s newest minute written.
pub fn last(connection: &Connection, node: &str) -> Result<Option<Minute>, StoreError> {
	let mut select = connection
		.prepare_cached("SELECT minute FROM minutes WHERE node = ?1 ORDER BY at DESC LIMIT 1")?;
	let mut rows = select.query_map(params![node], |row| row.get::<_, String>(0))?;
	Ok(match rows.next() {
		Some(minute) => Some(serde_json::from_str(&minute?)?),
		None => None,
	})
}

/// Writes `rows` where each is newer than what is written and not past keeping, then folds each
/// tier past keeping at `now` into the one above and drops it, in one transaction.
pub fn keep(
	connection: &mut Connection,
	rows: &[(String, Row)],
	now: i64,
) -> Result<(), StoreError> {
	let [minutes, hours, days] = kept(now);
	let transaction = connection.transaction()?;
	{
		let mut insert = transaction.prepare_cached(
			"INSERT INTO minutes (node, at, version, minute) VALUES (?1, ?2, ?3, ?4)
			ON CONFLICT (node, at) DO UPDATE SET version = excluded.version, minute = excluded.minute
			WHERE excluded.version > minutes.version",
		)?;
		for (node, row) in rows.iter().filter(|(_, row)| row.minute.at >= minutes) {
			let minute = serde_json::to_string(&row.minute)?;
			insert.execute(params![node, row.minute.at, stored(row.version), minute])?;
		}
	}
	let mut held = Vec::new();
	{
		let mut select = transaction
			.prepare_cached("SELECT node, at, minute FROM minutes WHERE at < ?1 ORDER BY node, at")?;
		let rows =
			select.query_map(params![minutes], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?;
		for row in rows {
			let (node, at, minute): (String, i64, String) = row?;
			held.push((node, at, MINUTE, Fold::minute(&serde_json::from_str(&minute)?)));
		}
	}
	let hourly = folded(&transaction, held, HOUR)?;
	write(&transaction, "hours", &hourly)?;
	transaction.execute("DELETE FROM minutes WHERE at < ?1", params![minutes])?;

	let held = folds(&transaction, "hours", i64::MIN, hours)?;
	let held = held.into_iter().map(|(node, at, fold)| (node, at, HOUR, fold)).collect();
	let daily = folded(&transaction, held, DAY)?;
	write(&transaction, "days", &daily)?;
	transaction.execute("DELETE FROM hours WHERE at < ?1", params![hours])?;
	transaction.execute("DELETE FROM days WHERE at < ?1", params![days])?;
	Ok(transaction.commit()?)
}

/// `held`, in order by node and start, each with its length, folded into units of `unit`: each
/// node's first from what was held before it, the rest each from the one before.
fn folded(
	connection: &Connection,
	held: Vec<(String, i64, i64, Fold)>,
	unit: i64,
) -> Result<Vec<(String, i64, Fold)>, StoreError> {
	// Each unit's parts, by start and end.
	type Parts = Vec<(i64, i64, Fold)>;
	let mut grouped: Vec<(String, i64, Parts)> = Vec::new();
	for (node, at, length, fold) in held {
		let start = floor(at, unit);
		match grouped.last_mut() {
			Some((last, from, parts)) if *last == node && *from == start => {
				parts.push((at, at + length, fold));
			}
			_ => grouped.push((node, start, vec![(at, at + length, fold)])),
		}
	}
	let mut folds: Vec<(String, i64, Fold)> = Vec::with_capacity(grouped.len());
	for (node, at, parts) in grouped {
		let leaving = match folds.last() {
			Some((last, _, fold)) if *last == node => fold.tail,
			_ => tails(connection, at)?.get(&node).is_some_and(|(_, tail)| *tail),
		};
		let parts = parts.iter().map(|(start, end, fold)| (*start, *end, fold));
		folds.push((node, at, Fold::of(at, at + unit, leaving, parts)));
	}
	Ok(folds)
}

/// Each node's last thing held before `at`, in any tier: its end, and whether its last minute said
/// the node was leaving.
pub fn tails(
	connection: &Connection,
	at: i64,
) -> Result<BTreeMap<String, (i64, bool)>, StoreError> {
	let mut tails: BTreeMap<String, (i64, i64, bool)> = BTreeMap::new();
	for (table, column, length) in
		[("minutes", "minute", MINUTE), ("hours", "fold", HOUR), ("days", "fold", DAY)]
	{
		let mut select = connection.prepare_cached(&format!(
			"SELECT node, MAX(at), {column} FROM {table} WHERE at < ?1 GROUP BY node"
		))?;
		let rows = select.query_map(params![at], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?;
		for row in rows {
			let (node, start, held): (String, i64, String) = row?;
			if tails.get(&node).is_some_and(|(later, ..)| *later >= start) {
				continue;
			}
			let tail = if table == "minutes" {
				serde_json::from_str::<Minute>(&held)?.leaving.is_some()
			} else {
				serde_json::from_str::<Fold>(&held)?.tail
			};
			tails.insert(node, (start, start + length, tail));
		}
	}
	Ok(tails.into_iter().map(|(node, (_, end, tail))| (node, (end, tail))).collect())
}

/// Folds made, each kept as first made: a unit is folded once, as its tier under is dropped.
fn write(
	transaction: &Transaction,
	table: &str,
	folds: &[(String, i64, Fold)],
) -> Result<(), StoreError> {
	let mut insert = transaction.prepare_cached(&format!(
		"INSERT OR IGNORE INTO {table} (node, at, fold) VALUES (?1, ?2, ?3)"
	))?;
	for (node, at, fold) in folds {
		insert.execute(params![node, at, serde_json::to_string(fold)?])?;
	}
	Ok(())
}

/// The folds of `table`, `hours` or `days`, from `from` until `until`, in order.
fn folds(
	connection: &Connection,
	table: &str,
	from: i64,
	until: i64,
) -> Result<Vec<(String, i64, Fold)>, StoreError> {
	let mut select = connection.prepare_cached(&format!(
		"SELECT node, at, fold FROM {table} WHERE at >= ?1 AND at < ?2 ORDER BY node, at"
	))?;
	let rows =
		select.query_map(params![from, until], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?;
	let mut folds = Vec::new();
	for row in rows {
		let (node, at, fold): (String, i64, String) = row?;
		folds.push((node, at, serde_json::from_str(&fold)?));
	}
	Ok(folds)
}

/// Each node's earliest moment held, in any tier.
pub fn first(connection: &Connection) -> Result<BTreeMap<String, i64>, StoreError> {
	let mut select = connection.prepare_cached(
		"SELECT node, MIN(at) FROM (
			SELECT node, at FROM minutes UNION ALL SELECT node, at FROM hours
			UNION ALL SELECT node, at FROM days
		) GROUP BY node",
	)?;
	let rows = select.query_map([], |row| Ok((row.get(0)?, row.get(1)?)))?;
	Ok(rows.collect::<rusqlite::Result<_>>()?)
}

/// What is held from `from` until `until`, each handed to `each` by node, start and length as a
/// fold, a minute as a fold of one, but a minute in `skip`, which memory holds newer.
pub fn each(
	connection: &Connection,
	from: i64,
	until: i64,
	skip: &BTreeSet<(String, i64)>,
	mut each: impl FnMut(&str, i64, i64, &Fold),
) -> Result<(), StoreError> {
	for (table, length) in [("days", DAY), ("hours", HOUR)] {
		for (node, at, fold) in folds(connection, table, from, until)? {
			each(&node, at, length, &fold);
		}
	}
	let mut select =
		connection.prepare_cached("SELECT node, at, minute FROM minutes WHERE at >= ?1 AND at < ?2")?;
	let rows =
		select.query_map(params![from, until], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?;
	for row in rows {
		let (node, at, minute): (String, i64, String) = row?;
		if skip.contains(&(node.clone(), at)) {
			continue;
		}
		each(&node, at, MINUTE, &Fold::minute(&serde_json::from_str(&minute)?));
	}
	Ok(())
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::presence::Reason;
	use crate::runs::Store;

	/// Midnight on 2026-10-09, in milliseconds.
	const DAWN: i64 = 1_791_504_000_000;

	fn row(at: i64, leaving: bool) -> (String, Row) {
		let leaving = leaving.then_some(Reason::Upgrade);
		let minute = Minute {
			at,
			beats: 20,
			down: BTreeMap::new(),
			held: 0,
			round_trip: BTreeMap::new(),
			leaving,
		};
		("tyo".into(), Row { version: 1, minute })
	}

	fn held(connection: &Connection, table: &str) -> Vec<(i64, u32, u32, bool)> {
		let folds = folds(connection, table, i64::MIN, i64::MAX).unwrap();
		folds.into_iter().map(|(_, at, fold)| (at, fold.minutes, fold.announced, fold.tail)).collect()
	}

	#[test]
	fn minutes_fold_into_hours_then_days_as_each_tier_ages_and_days_go_after_a_year() {
		let mut store = Store::memory().unwrap();
		let connection = store.connection();
		let (a, b) = (DAWN + 22 * HOUR, DAWN + 23 * HOUR);
		// Leaving said in a's first minute, back four minutes later; leaving again halfway through b.
		let rows =
			[row(a, true), row(a + 5 * MINUTE, false), row(b, false), row(b + 30 * MINUTE, true)];
		keep(connection, &rows, DAWN + 2 * DAY).unwrap();
		assert!(held(connection, "hours").is_empty());

		// Two days on from b's end, both hours fold, and their minutes go.
		keep(connection, &[], DAWN + 3 * DAY).unwrap();
		assert_eq!(held(connection, "hours"), [(a, 2, 4, false), (b, 2, 29, true)]);
		assert!(above(connection, "tyo", 0).unwrap().is_empty());
		// A minute that old, arriving late, is past keeping and is not written.
		keep(connection, &[row(a + 10 * MINUTE, false)], DAWN + 3 * DAY).unwrap();
		assert!(above(connection, "tyo", 0).unwrap().is_empty());
		assert_eq!(tails(connection, DAWN + 3 * DAY).unwrap()["tyo"], (b + HOUR, true));

		// Thirty days on from the day's end, the hours fold into the day.
		keep(connection, &[], DAWN + 32 * DAY).unwrap();
		assert!(held(connection, "hours").is_empty());
		assert_eq!(held(connection, "days"), [(DAWN, 4, 33, true)]);

		keep(connection, &[], DAWN + 402 * DAY).unwrap();
		assert!(held(connection, "days").is_empty());
	}

	#[test]
	fn an_hour_with_no_minute_before_it_held_starts_unannounced_and_one_after_a_fold_follows_it() {
		let mut store = Store::memory().unwrap();
		let connection = store.connection();
		let a = DAWN + 22 * HOUR;
		keep(connection, &[row(a + 59 * MINUTE, true)], DAWN + 2 * DAY).unwrap();
		keep(connection, &[], DAWN + 3 * DAY).unwrap();
		// The next hour folded on a later write starts from a's word, read from a's fold.
		let next = a + 3 * HOUR;
		keep(connection, &[row(next + 2 * MINUTE, false)], DAWN + 3 * DAY).unwrap();
		keep(connection, &[], DAWN + 4 * DAY).unwrap();
		assert_eq!(held(connection, "hours"), [(a, 1, 0, true), (next, 1, 2, false)]);
	}
}
