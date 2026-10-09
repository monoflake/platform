//! Every node's runs: host's event rows, each tagged with the node it happened on, for the last
//! 30 days. What changed lately is held in memory, the window, and spread on the mesh; the rest is
//! in `runs.db`. See spec/architecture/relay.md, "The runs, mirrored on every relay's disk".

use crate::cluster::Versions;
use crate::host::Event;
use jiff::Timestamp;
use rusqlite::{Connection, params};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::time::Duration;

/// The file in the relay's data directory.
pub const FILE: &str = "runs.db";

/// What changed this lately is held in memory, written or not.
pub const WINDOW: Duration = Duration::from_secs(3 * 60);

/// How often the window is written: six chances a row inside it.
pub const WRITE: Duration = Duration::from_secs(30);

/// How far back a node's rows are kept, by when each started.
pub const KEPT: Duration = Duration::from_secs(30 * 24 * 60 * 60);

/// The most rows kept of one node, the oldest going first.
pub const MOST: usize = 5000;

/// A row as it travels between relays: host's event, and the version its origin gave it.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Row {
	pub version: u64,
	#[serde(flatten)]
	pub event: Event,
}

/// Some of one node's rows: every row of it above `above` that the sender holds, which holds
/// every row through `version`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Batch {
	pub node: String,
	pub above: u64,
	pub version: u64,
	pub rows: Vec<Row>,
}

/// A row as `/runs` answers it: host's event, and the node it happened on.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Shown {
	pub node: String,
	#[serde(flatten)]
	pub event: Event,
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
	#[error("the file refused: {0}")]
	Refused(#[from] rusqlite::Error),
	#[error("a row in the file is not an event: {0}")]
	Malformed(#[from] serde_json::Error),
	#[error("the thread reading the file stopped: {0}")]
	Stopped(#[from] tokio::task::JoinError),
	#[error("the broken file could not be moved aside: {0}")]
	Aside(#[from] std::io::Error),
}

/// When a row started, in milliseconds. A row whose start is no timestamp is not mirrored: it
/// could be neither ordered nor aged.
fn started(event: &Event) -> Option<i64> {
	event.started_at.parse::<Timestamp>().ok().map(Timestamp::as_millisecond)
}

/// A version as SQLite holds it, an integer of 64 bits with a sign; one in milliseconds fits.
fn stored(version: u64) -> i64 {
	i64::try_from(version).unwrap_or(i64::MAX)
}

fn loaded(version: i64) -> u64 {
	u64::try_from(version).unwrap_or(0)
}

fn milliseconds(duration: Duration) -> i64 {
	i64::try_from(duration.as_millis()).unwrap_or(i64::MAX)
}

/// The oldest start kept at `now`.
fn cutoff(now: Timestamp) -> i64 {
	now.as_millisecond().saturating_sub(milliseconds(KEPT))
}

/// The millisecond it is, or one past the last when the clock has not moved on, as a snapshot's
/// version is: see `own::version_after`.
fn version_after(last: u64, now: Timestamp) -> u64 {
	let now = u64::try_from(now.as_millisecond()).unwrap_or(0);
	now.max(last + 1)
}

/// `runs.db`: every row written, by node and id, the newer version kept.
pub struct Store {
	connection: Connection,
}

impl Store {
	/// The file at `path`, or a fresh one where it cannot be opened: the broken one is moved aside
	/// with why logged, and the mirror is rebuilt from host and the neighbors. A file that cannot be
	/// moved, or a fresh one that cannot be opened, is an error.
	pub fn open(path: &Path) -> Result<Self, StoreError> {
		let error = match Connection::open(path).map_err(StoreError::from).and_then(Self::ready) {
			Ok(store) => return Ok(store),
			Err(error) => error,
		};
		let aside = aside(path, Timestamp::now());
		std::fs::rename(path, &aside)?;
		for suffix in ["-wal", "-shm"] {
			match std::fs::rename(suffixed(path, suffix), suffixed(&aside, suffix)) {
				Err(missing) if missing.kind() == std::io::ErrorKind::NotFound => {}
				moved => moved?,
			}
		}
		eprintln!("relay: {} moved aside to {}: {error}", path.display(), aside.display());
		Self::ready(Connection::open(path)?)
	}

	/// A store kept in memory, for the tests.
	pub fn memory() -> Result<Self, StoreError> {
		Self::ready(Connection::open_in_memory()?)
	}

	fn ready(connection: Connection) -> Result<Self, StoreError> {
		connection.execute_batch(
			"PRAGMA journal_mode = WAL;
			PRAGMA synchronous = NORMAL;
			PRAGMA busy_timeout = 5000;
			CREATE TABLE IF NOT EXISTS runs (
				node TEXT NOT NULL,
				id INTEGER NOT NULL,
				version INTEGER NOT NULL,
				started INTEGER NOT NULL,
				event TEXT NOT NULL,
				PRIMARY KEY (node, id)
			) WITHOUT ROWID;
			CREATE INDEX IF NOT EXISTS runs_version ON runs (node, version);
			CREATE INDEX IF NOT EXISTS runs_started ON runs (node, started);",
		)?;
		Ok(Self { connection })
	}

	/// The newest version written, by node.
	pub fn held(&self) -> Result<Versions, StoreError> {
		let mut select =
			self.connection.prepare("SELECT node, MAX(version) FROM runs GROUP BY node")?;
		let rows = select.query_map([], |row| Ok((row.get(0)?, loaded(row.get(1)?))))?;
		Ok(rows.collect::<rusqlite::Result<_>>()?)
	}

	/// Writes `rows` where each is newer than what is written, then drops what is past keeping at
	/// `now`, in one transaction.
	pub fn keep(&mut self, rows: &[(String, Row)], now: Timestamp) -> Result<(), StoreError> {
		let transaction = self.connection.transaction()?;
		{
			let mut insert = transaction.prepare_cached(
				"INSERT INTO runs (node, id, version, started, event) VALUES (?1, ?2, ?3, ?4, ?5)
				ON CONFLICT (node, id) DO UPDATE SET
					version = excluded.version, started = excluded.started, event = excluded.event
				WHERE excluded.version > runs.version",
			)?;
			for (node, row) in rows {
				let Some(started) = started(&row.event) else { continue };
				let event = serde_json::to_string(&row.event)?;
				insert.execute(params![node, row.event.id, stored(row.version), started, event])?;
			}
		}
		transaction.execute("DELETE FROM runs WHERE started < ?1", params![cutoff(now)])?;
		transaction.execute(
			"DELETE FROM runs WHERE (node, id) IN (
				SELECT node, id FROM (
					SELECT node, id,
						ROW_NUMBER() OVER (PARTITION BY node ORDER BY started DESC, id DESC) AS place
					FROM runs
				) WHERE place > ?1
			)",
			params![i64::try_from(MOST).unwrap_or(i64::MAX)],
		)?;
		Ok(transaction.commit()?)
	}

	/// `node`'s rows above `version`.
	pub fn above(&self, node: &str, version: u64) -> Result<Vec<Row>, StoreError> {
		let mut select = self
			.connection
			.prepare_cached("SELECT version, event FROM runs WHERE node = ?1 AND version > ?2")?;
		let rows =
			select.query_map(params![node, stored(version)], |row| Ok((row.get(0)?, row.get(1)?)))?;
		let mut above = Vec::new();
		for row in rows {
			let (version, event): (i64, String) = row?;
			above.push(Row { version: loaded(version), event: serde_json::from_str(&event)? });
		}
		Ok(above)
	}

	/// Every node's rows that started at `from` or later.
	pub fn since(&self, from: i64) -> Result<Vec<(String, Row)>, StoreError> {
		let mut select = self
			.connection
			.prepare_cached("SELECT node, version, event FROM runs WHERE started >= ?1")?;
		let rows =
			select.query_map(params![from], |row| Ok((row.get(0)?, row.get(1)?, row.get(2)?)))?;
		let mut since = Vec::new();
		for row in rows {
			let (node, version, event): (String, i64, String) = row?;
			since.push((node, Row { version: loaded(version), event: serde_json::from_str(&event)? }));
		}
		Ok(since)
	}
}

/// Where a broken file goes: `runs.db.broken-<unix seconds>`, its `-wal` and `-shm` beside it as
/// SQLite would name them.
fn aside(path: &Path, now: Timestamp) -> PathBuf {
	suffixed(path, &format!(".broken-{}", now.as_second()))
}

fn suffixed(path: &Path, suffix: &str) -> PathBuf {
	let mut named = path.as_os_str().to_owned();
	named.push(suffix);
	named.into()
}

/// A row held in memory, and whether a write has taken it at this version.
#[derive(Debug, Clone)]
struct Kept {
	row: Row,
	written: bool,
}

/// What a neighbor lacks of one node.
#[derive(Debug, PartialEq)]
pub enum Lack {
	/// Memory holds every row it lacks.
	Held(Batch),
	/// It is behind what memory holds: the file's rows above `above` go with these.
	Behind(Batch),
}

/// The window, and what it takes to tell what is new: in memory, never blocking.
#[derive(Debug)]
pub struct Window {
	node: String,
	/// By node, the version through which every row is held, here or in the file.
	held: Versions,
	/// By node, the newest version gone from memory: every row above it is still here.
	floor: Versions,
	rows: BTreeMap<(String, i64), Kept>,
	/// This node's own rows as last read, to tell a row read again from one read changed.
	seen: BTreeMap<i64, Event>,
}

impl Window {
	/// Opened over a file holding `held`, and this node's own rows from it.
	pub fn new(node: String, held: Versions, own: Vec<Row>) -> Self {
		let seen = own.into_iter().map(|row| (row.event.id, row.event)).collect();
		Self { node, floor: held.clone(), held, rows: BTreeMap::new(), seen }
	}

	/// This node's rows as host answered them: those new or changed, under one new version, as the
	/// batch its neighbors are pushed.
	pub fn observe(&mut self, events: &[Event], now: Timestamp) -> Option<Batch> {
		let from = cutoff(now);
		let changed: Vec<Event> = events
			.iter()
			.filter(|event| started(event).is_some_and(|started| started >= from))
			.filter(|event| self.seen.get(&event.id) != Some(*event))
			.cloned()
			.collect();
		if changed.is_empty() {
			return None;
		}
		let above = self.held.get(&self.node).copied().unwrap_or(0);
		let version = version_after(above, now);
		self.held.insert(self.node.clone(), version);
		let mut rows = Vec::with_capacity(changed.len());
		for event in changed {
			self.seen.insert(event.id, event.clone());
			let row = Row { version, event };
			let kept = Kept { row: row.clone(), written: false };
			self.rows.insert((self.node.clone(), row.event.id), kept);
			rows.push(row);
		}
		Some(Batch { node: self.node.clone(), above, version, rows })
	}

	/// Takes a neighbor's batch when it follows on from what is held of its node; whether it did.
	/// One that does not leaves a gap, which the next comparison fills. This node's own rows are
	/// never taken: its host is their one source.
	pub fn merge(&mut self, batch: Batch) -> bool {
		let Batch { node, above, version, rows } = batch;
		let held = self.held.get(&node).copied().unwrap_or(0);
		if node == self.node || above > held {
			return false;
		}
		let mut newest = version.max(held);
		for row in rows {
			// Every row through `held` is held already, and at least as new.
			if row.version <= held || started(&row.event).is_none() {
				continue;
			}
			newest = newest.max(row.version);
			self.rows.insert((node.clone(), row.event.id), Kept { row, written: false });
		}
		self.held.insert(node, newest);
		newest > held
	}

	pub fn versions(&self) -> Versions {
		self.held.clone()
	}

	/// What `peer`, holding `theirs`, lacks: every node held newer here, but never `peer`'s own.
	pub fn lacking(&self, theirs: &Versions, peer: &str) -> Vec<Lack> {
		let mut lacking = Vec::new();
		for (node, &version) in &self.held {
			let above = theirs.get(node).copied().unwrap_or(0);
			if node == peer || version <= above {
				continue;
			}
			let rows = self.held_above(node, above);
			let batch = Batch { node: node.clone(), above, version, rows };
			let floor = self.floor.get(node).copied().unwrap_or(0);
			lacking.push(if above >= floor { Lack::Held(batch) } else { Lack::Behind(batch) });
		}
		lacking
	}

	fn held_above(&self, node: &str, above: u64) -> Vec<Row> {
		self
			.rows
			.range((node.to_owned(), i64::MIN)..=(node.to_owned(), i64::MAX))
			.filter(|(_, kept)| kept.row.version > above)
			.map(|(_, kept)| kept.row.clone())
			.collect()
	}

	/// The rows no write has taken yet.
	pub fn unwritten(&self) -> Vec<(String, Row)> {
		self
			.rows
			.iter()
			.filter(|(_, kept)| !kept.written)
			.map(|((node, _), kept)| (node.clone(), kept.row.clone()))
			.collect()
	}

	/// The rows a write took, marked as written where memory still holds them at that version.
	pub fn written(&mut self, taken: &[(String, Row)]) {
		for (node, row) in taken {
			if let Some(kept) = self.rows.get_mut(&(node.clone(), row.event.id))
				&& kept.row.version == row.version
			{
				kept.written = true;
			}
		}
	}

	/// Lets go of each row written and older than the window, and of this node's own rows past
	/// keeping, as the file drops them.
	pub fn evict(&mut self, now: Timestamp) {
		let old = u64::try_from(now.as_millisecond().saturating_sub(milliseconds(WINDOW))).unwrap_or(0);
		let floor = &mut self.floor;
		self.rows.retain(|(node, _), kept| {
			let going = kept.written && kept.row.version < old;
			if going {
				let at = floor.entry(node.clone()).or_insert(0);
				*at = (*at).max(kept.row.version);
			}
			!going
		});

		let from = cutoff(now);
		self.seen.retain(|_, event| started(event).is_some_and(|started| started >= from));
		if self.seen.len() > MOST {
			let mut order: Vec<(i64, i64)> =
				self.seen.values().filter_map(|event| Some((started(event)?, event.id))).collect();
			order.sort_unstable_by(|a, b| b.cmp(a));
			for (_, id) in order.split_off(MOST) {
				self.seen.remove(&id);
			}
		}
	}

	/// Every row held in memory, by node.
	fn rows(&self) -> impl Iterator<Item = (&str, &Row)> {
		self.rows.iter().map(|((node, _), kept)| (node.as_str(), &kept.row))
	}
}

/// Each row by node and id, the newer version kept of two.
fn newest(rows: impl IntoIterator<Item = (String, Row)>) -> BTreeMap<(String, i64), Row> {
	let mut newest: BTreeMap<(String, i64), Row> = BTreeMap::new();
	for (node, row) in rows {
		let key = (node, row.event.id);
		if newest.get(&key).is_none_or(|held| held.version < row.version) {
			newest.insert(key, row);
		}
	}
	newest
}

/// The window and the file together, each read of the file off the async threads.
pub struct Mirror {
	window: Mutex<Window>,
	store: Arc<Mutex<Store>>,
}

fn lock<T>(mutex: &Mutex<T>) -> MutexGuard<'_, T> {
	mutex.lock().unwrap_or_else(PoisonError::into_inner)
}

impl Mirror {
	/// The file read: what it holds of each node, and this node's own rows.
	pub fn open(node: String, store: Store) -> Result<Self, StoreError> {
		let held = store.held()?;
		let own = store.above(&node, 0)?;
		let window = Window::new(node, held, own);
		Ok(Self { window: Mutex::new(window), store: Arc::new(Mutex::new(store)) })
	}

	pub fn observe(&self, events: &[Event], now: Timestamp) -> Option<Batch> {
		lock(&self.window).observe(events, now)
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
					let written = self.blocking(move |store| store.above(&node, above)).await?;
					let both = written.into_iter().chain(batch.rows).map(|row| (String::new(), row));
					let rows = newest(both).into_values().collect();
					Batch { rows, ..batch }
				}
			});
		}
		Ok(batches)
	}

	/// Writes what the window holds unwritten and drops what is past keeping, then lets go of what
	/// memory no longer needs. A refusal leaves every row unwritten for the next.
	pub async fn write(&self, now: Timestamp) -> Result<(), StoreError> {
		let unwritten = lock(&self.window).unwritten();
		let taken = self
			.blocking(move |store| {
				store.keep(&unwritten, now)?;
				Ok(unwritten)
			})
			.await?;
		let mut window = lock(&self.window);
		window.written(&taken);
		window.evict(now);
		Ok(())
	}

	/// Every node's rows that started within `KEPT` of `now`, from the file and the window, newest
	/// first.
	pub async fn listed(&self, now: Timestamp) -> Result<Vec<Shown>, StoreError> {
		let from = cutoff(now);
		let written = self.blocking(move |store| store.since(from)).await?;
		let held: Vec<(String, Row)> =
			lock(&self.window).rows().map(|(node, row)| (node.to_owned(), row.clone())).collect();
		let mut listed: Vec<(i64, Shown)> = newest(written.into_iter().chain(held))
			.into_iter()
			.filter_map(|((node, _), row)| {
				let started = started(&row.event).filter(|started| *started >= from)?;
				Some((started, Shown { node, event: row.event }))
			})
			.collect();
		listed.sort_by(|(a, x), (b, y)| (b, y.event.id, &y.node).cmp(&(a, x.event.id, &x.node)));
		Ok(listed.into_iter().map(|(_, shown)| shown).collect())
	}

	async fn blocking<T: Send + 'static>(
		&self,
		read: impl FnOnce(&mut Store) -> Result<T, StoreError> + Send + 'static,
	) -> Result<T, StoreError> {
		let store = self.store.clone();
		tokio::task::spawn_blocking(move || read(&mut lock(&store))).await?
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::host::Source;

	/// A moment on 2026-10-09, and `seconds` after it.
	fn at(seconds: i64) -> Timestamp {
		Timestamp::from_second(1_791_500_000 + seconds).unwrap()
	}

	fn event(id: i64, outcome: &str, started_at: Timestamp) -> Event {
		Event {
			id,
			app: "geo".into(),
			action: "deploy".into(),
			source: Source { kind: "run".into(), run: Some(18734), commit: None },
			image: None,
			outcome: outcome.into(),
			stage: None,
			detail: None,
			started_at: started_at.to_string(),
			finished_at: None,
		}
	}

	fn row(id: i64, version: u64, started_at: Timestamp) -> Row {
		Row { version, event: event(id, "succeeded", started_at) }
	}

	fn window(node: &str) -> Window {
		Window::new(node.into(), Versions::new(), vec![])
	}

	fn ms(at: Timestamp) -> u64 {
		u64::try_from(at.as_millisecond()).unwrap()
	}

	#[test]
	fn a_row_is_versioned_when_first_read_and_again_when_it_changes() {
		let mut window = window("rdu");
		let first = window.observe(&[event(1, "running", at(0))], at(0)).unwrap();
		assert_eq!((first.above, first.version), (0, ms(at(0))));
		assert_eq!(first.rows[0].version, ms(at(0)));

		// Read again unchanged, nothing; another row new and one moved on, both one new version.
		assert!(window.observe(&[event(1, "running", at(0))], at(3)).is_none());
		let read = [event(2, "running", at(3)), event(1, "succeeded", at(0))];
		let second = window.observe(&read, at(6)).unwrap();
		assert_eq!((second.above, second.version), (ms(at(0)), ms(at(6))));
		assert_eq!(second.rows.len(), 2);
		assert_eq!(window.versions(), Versions::from([("rdu".into(), ms(at(6)))]));
	}

	#[test]
	fn a_version_climbs_when_the_clock_does_not_and_starts_above_the_file() {
		// The file holds a version ahead of the clock, as after a restart within a millisecond.
		let held = Versions::from([("rdu".into(), ms(at(0)) + 5)]);
		let mut window = Window::new("rdu".into(), held, vec![]);
		let batch = window.observe(&[event(1, "running", at(0))], at(0)).unwrap();
		assert_eq!(batch.version, ms(at(0)) + 6);
		let batch = window.observe(&[event(1, "succeeded", at(0))], at(0)).unwrap();
		assert_eq!(batch.version, ms(at(0)) + 7);
	}

	#[test]
	fn the_files_own_rows_are_not_versioned_again() {
		let own = vec![row(1, 7, at(0))];
		let mut window = Window::new("rdu".into(), Versions::from([("rdu".into(), 7)]), own);
		assert!(window.observe(&[event(1, "succeeded", at(0))], at(9)).is_none());
	}

	#[test]
	fn rows_past_keeping_or_with_no_start_are_not_mirrored() {
		let mut window = window("rdu");
		let old = at(0) - KEPT - Duration::from_secs(1);
		let mut unstarted = event(2, "running", at(0));
		unstarted.started_at = "yesterday".into();
		assert!(window.observe(&[event(1, "succeeded", old), unstarted], at(0)).is_none());
	}

	#[test]
	fn a_row_stays_until_it_is_written_and_older_than_the_window() {
		let mut window = window("rdu");
		window.observe(&[event(1, "running", at(0))], at(0));

		// Older than the window, but no write has taken it.
		window.evict(at(600));
		assert_eq!(window.unwritten().len(), 1);

		// Written, but not yet older than the window.
		let mut window = self::window("rdu");
		window.observe(&[event(1, "running", at(0))], at(0));
		let taken = window.unwritten();
		window.written(&taken);
		assert!(window.unwritten().is_empty());
		window.evict(at(179));
		assert_eq!(window.rows().count(), 1);
		window.evict(at(181));
		assert_eq!(window.rows().count(), 0);
	}

	#[test]
	fn a_row_changed_after_a_write_took_it_is_still_unwritten() {
		let mut window = window("rdu");
		window.observe(&[event(1, "running", at(0))], at(0));
		let taken = window.unwritten();
		window.observe(&[event(1, "succeeded", at(0))], at(1));
		window.written(&taken);
		let unwritten = window.unwritten();
		assert_eq!(unwritten.len(), 1);
		assert_eq!(unwritten[0].1.event.outcome, "succeeded");
	}

	#[test]
	fn a_neighbors_batch_is_taken_when_it_follows_on_and_the_newer_row_wins() {
		let mut window = window("rdu");
		let first = Batch { node: "tyo".into(), above: 0, version: 10, rows: vec![row(1, 10, at(0))] };
		assert!(window.merge(first));
		// A gap: above what is held of tyo.
		let gap = Batch { node: "tyo".into(), above: 15, version: 20, rows: vec![row(2, 20, at(0))] };
		assert!(!window.merge(gap));
		assert_eq!(window.versions()["tyo"], 10);

		// Follows on, and carries row 1 at a newer version and again at the one held.
		let mut newer = row(1, 12, at(0));
		newer.event.outcome = "failed".into();
		let rows = vec![row(1, 10, at(0)), newer, row(2, 11, at(1))];
		assert!(window.merge(Batch { node: "tyo".into(), above: 5, version: 12, rows }));
		let held: BTreeMap<i64, (u64, String)> = window
			.rows()
			.map(|(_, row)| (row.event.id, (row.version, row.event.outcome.clone())))
			.collect();
		assert_eq!(held, BTreeMap::from([(1, (12, "failed".into())), (2, (11, "succeeded".into()))]));
		assert_eq!(window.versions()["tyo"], 12);

		// What is held already is not taken again, and this node's own rows never are.
		let again = Batch { node: "tyo".into(), above: 0, version: 12, rows: vec![row(1, 9, at(0))] };
		assert!(!window.merge(again));
		let own = Batch { node: "rdu".into(), above: 0, version: 9, rows: vec![row(1, 9, at(0))] };
		assert!(!window.merge(own));
	}

	#[test]
	fn a_neighbor_behind_what_memory_holds_is_answered_from_the_file() {
		let mut window = window("rdu");
		window.merge(Batch {
			node: "tyo".into(),
			above: 0,
			version: 10,
			rows: vec![row(1, 10, at(0))],
		});
		window.observe(&[event(1, "running", at(0))], at(0));
		let taken = window.unwritten();
		window.written(&taken);
		window.evict(at(600));
		window.merge(Batch {
			node: "tyo".into(),
			above: 10,
			version: 20,
			rows: vec![row(2, 20, at(0))],
		});

		let theirs = Versions::from([("tyo".into(), 10), ("rdu".into(), 0)]);
		let lacking = window.lacking(&theirs, "buf");
		assert_eq!(lacking.len(), 2);
		// rdu's row left memory, so a neighbor holding none of it is behind; tyo's 20 is still here.
		assert!(
			matches!(&lacking[0], Lack::Behind(batch) if batch.node == "rdu" && batch.rows.is_empty())
		);
		assert!(matches!(&lacking[1], Lack::Held(batch)
			if batch.node == "tyo" && batch.above == 10 && batch.rows == [row(2, 20, at(0))]));
		// Never a neighbor's own rows.
		assert!(window.lacking(&Versions::new(), "tyo").iter().all(|lack| match lack {
			Lack::Held(batch) | Lack::Behind(batch) => batch.node != "tyo",
		}));
	}

	#[test]
	fn the_file_keeps_the_newer_version_and_drops_past_keeping() {
		let mut store = Store::memory().unwrap();
		let now = at(0);
		let mut newer = row(1, 12, now);
		newer.event.outcome = "failed".into();
		store.keep(&[("tyo".into(), newer.clone())], now).unwrap();
		store.keep(&[("tyo".into(), row(1, 10, now))], now).unwrap();
		assert_eq!(store.above("tyo", 0).unwrap(), [newer]);

		let old = now - KEPT - Duration::from_secs(1);
		store.keep(&[("tyo".into(), row(2, 13, old))], now).unwrap();
		assert_eq!(store.above("tyo", 12).unwrap(), []);
		assert_eq!(store.held().unwrap(), Versions::from([("tyo".into(), 12)]));
	}

	#[test]
	fn the_file_keeps_the_newest_rows_of_each_node_up_to_the_most() {
		let mut store = Store::memory().unwrap();
		let now = at(0);
		let many: Vec<(String, Row)> = (0..=i64::try_from(MOST).unwrap())
			.map(|id| ("tyo".into(), row(id, 1, now - Duration::from_secs(id.unsigned_abs()))))
			.chain([("rdu".into(), row(0, 1, now))])
			.collect();
		store.keep(&many, now).unwrap();
		let tyo = store.above("tyo", 0).unwrap();
		assert_eq!(tyo.len(), MOST);
		// The one that started first went.
		assert!(tyo.iter().all(|row| row.event.id != i64::try_from(MOST).unwrap()));
		assert_eq!(store.above("rdu", 0).unwrap().len(), 1);
	}

	#[tokio::test]
	async fn listed_merges_the_file_and_the_window_newest_first() {
		let mirror = Mirror::open("rdu".into(), Store::memory().unwrap()).unwrap();
		mirror.observe(&[event(1, "running", at(0)), event(2, "succeeded", at(-60))], at(0));
		mirror.write(at(0)).await.unwrap();
		// Written, then moved on in memory alone.
		mirror.observe(&[event(1, "succeeded", at(0))], at(3));
		let tyo = Batch { node: "tyo".into(), above: 0, version: 4, rows: vec![row(9, 4, at(0))] };
		mirror.merge(tyo);

		let listed = mirror.listed(at(5)).await.unwrap();
		let order: Vec<(&str, i64, &str)> = listed
			.iter()
			.map(|shown| (shown.node.as_str(), shown.event.id, shown.event.outcome.as_str()))
			.collect();
		assert_eq!(order, [("tyo", 9, "succeeded"), ("rdu", 1, "succeeded"), ("rdu", 2, "succeeded")]);
		let written = serde_json::to_value(&listed[0]).unwrap();
		assert_eq!((&written["node"], &written["id"]), (&"tyo".into(), &9.into()));
		assert!(written.get("version").is_none());
	}

	#[tokio::test]
	async fn a_neighbor_behind_gets_the_file_and_the_window_together() {
		let mirror = Mirror::open("rdu".into(), Store::memory().unwrap()).unwrap();
		mirror.observe(&[event(1, "running", at(0)), event(2, "running", at(0))], at(0));
		mirror.write(at(0)).await.unwrap();
		mirror.write(at(600)).await.unwrap();
		// Row 2 moves on after row 1 left memory.
		mirror.observe(&[event(2, "succeeded", at(0))], at(601));

		let batches = mirror.lacking(&Versions::new(), "tyo").await.unwrap();
		assert_eq!(batches.len(), 1);
		let rows: Vec<(i64, &str)> =
			batches[0].rows.iter().map(|row| (row.event.id, row.event.outcome.as_str())).collect();
		assert_eq!(rows, [(1, "running"), (2, "succeeded")]);
	}

	#[test]
	fn a_file_that_is_no_database_is_moved_aside_and_a_fresh_one_opened() {
		let directory = tempfile::tempdir().unwrap();
		let path = directory.path().join(FILE);
		std::fs::write(&path, "not a database, not at all, whatever it says").unwrap();

		let mut store = Store::open(&path).unwrap();
		assert_eq!(store.held().unwrap(), Versions::new());
		store.keep(&[("tyo".into(), row(1, 4, at(0)))], at(0)).unwrap();
		assert_eq!(store.held().unwrap(), Versions::from([("tyo".into(), 4)]));

		// Read alone, a `-wal` that is no log is let go of by SQLite as it closes; one it keeps
		// goes aside with the file.
		let names: Vec<String> = std::fs::read_dir(directory.path())
			.unwrap()
			.map(|entry| entry.unwrap().file_name().into_string().unwrap())
			.filter(|name| name.contains(".broken-"))
			.collect();
		assert_eq!(names.len(), 1, "{names:?}");
		assert!(names[0].starts_with("runs.db.broken-"));
		let moved = std::fs::read_to_string(directory.path().join(&names[0])).unwrap();
		assert!(moved.starts_with("not a database"));
	}

	#[test]
	fn a_file_that_cannot_be_moved_aside_is_an_error() {
		let directory = tempfile::tempdir().unwrap();
		let path = directory.path().join("missing").join(FILE);
		assert!(matches!(Store::open(&path), Err(StoreError::Aside(_))));
	}

	#[tokio::test]
	async fn a_relay_restarted_reads_what_its_file_holds() {
		let directory = tempfile::tempdir().unwrap();
		let path = directory.path().join(FILE);
		{
			let mirror = Mirror::open("rdu".into(), Store::open(&path).unwrap()).unwrap();
			mirror.observe(&[event(1, "running", at(0))], at(0));
			mirror.merge(Batch {
				node: "tyo".into(),
				above: 0,
				version: 4,
				rows: vec![row(9, 4, at(0))],
			});
			mirror.write(at(0)).await.unwrap();
		}
		let mirror = Mirror::open("rdu".into(), Store::open(&path).unwrap()).unwrap();
		assert_eq!(mirror.versions(), Versions::from([("rdu".into(), ms(at(0))), ("tyo".into(), 4)]));
		assert!(mirror.observe(&[event(1, "running", at(0))], at(9)).is_none());
	}
}
