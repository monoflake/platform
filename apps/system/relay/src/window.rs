//! Every node's versioned rows as a relay holds them in memory: what changed lately, spread on the
//! mesh, the rest in the file. A node's rows have one writer, its own relay, and a neighbor's are
//! taken by comparing versions. The runs and the minutes are both kept this way. See
//! spec/architecture/relay.md, "The runs, mirrored on every relay's disk".

use crate::cluster::Versions;
use jiff::Timestamp;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::time::Duration;

/// A row of one node's, which its origin gave a version.
pub trait Versioned: Clone {
	fn version(&self) -> u64;
	/// Its place among its node's rows: an id, or a minute.
	fn key(&self) -> i64;
	/// Whether a neighbor's row can be kept at all.
	fn kept(&self) -> bool;
}

/// Some of one node's rows: every row of it above `above` that the sender holds, which holds
/// every row through `version`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Batch<R> {
	pub node: String,
	pub above: u64,
	pub version: u64,
	pub rows: Vec<R>,
}

/// What a neighbor lacks of one node.
#[derive(Debug, PartialEq)]
pub enum Lack<R> {
	/// Memory holds every row it lacks.
	Held(Batch<R>),
	/// It is behind what memory holds: the file's rows above `above` go with these.
	Behind(Batch<R>),
}

/// A row held in memory, and whether a write has taken it at this version.
#[derive(Debug, Clone)]
struct Kept<R> {
	row: R,
	written: bool,
}

/// The millisecond it is, or one past the last when the clock has not moved on, as a snapshot's
/// version is: see `own::version_after`.
pub fn version_after(last: u64, now: Timestamp) -> u64 {
	let now = u64::try_from(now.as_millisecond()).unwrap_or(0);
	now.max(last + 1)
}

pub fn milliseconds(duration: Duration) -> i64 {
	i64::try_from(duration.as_millis()).unwrap_or(i64::MAX)
}

#[derive(Debug)]
pub struct Window<R> {
	node: String,
	/// By node, the version through which every row is held, here or in the file.
	held: Versions,
	/// By node, the newest version gone from memory: every row above it is still here.
	floor: Versions,
	rows: BTreeMap<(String, i64), Kept<R>>,
}

impl<R: Versioned> Window<R> {
	/// Opened over a file holding `held`.
	pub fn new(node: String, held: Versions) -> Self {
		Self { node, floor: held.clone(), held, rows: BTreeMap::new() }
	}

	/// This node's own new rows, under one new version `made` is given, as the batch its neighbors
	/// are pushed.
	pub fn own(&mut self, now: Timestamp, made: impl FnOnce(u64) -> Vec<R>) -> Batch<R> {
		let above = self.held.get(&self.node).copied().unwrap_or(0);
		let version = version_after(above, now);
		self.held.insert(self.node.clone(), version);
		let rows = made(version);
		for row in &rows {
			let kept = Kept { row: row.clone(), written: false };
			self.rows.insert((self.node.clone(), row.key()), kept);
		}
		Batch { node: self.node.clone(), above, version, rows }
	}

	/// Takes a neighbor's batch when it follows on from what is held of its node; whether it did.
	/// One that does not leaves a gap, which the next comparison fills. This node's own rows are
	/// never taken: it is their one writer.
	pub fn merge(&mut self, batch: Batch<R>) -> bool {
		let Batch { node, above, version, rows } = batch;
		let held = self.held.get(&node).copied().unwrap_or(0);
		if node == self.node || above > held {
			return false;
		}
		let mut newest = version.max(held);
		for row in rows {
			// Every row through `held` is held already, and at least as new.
			if row.version() <= held || !row.kept() {
				continue;
			}
			newest = newest.max(row.version());
			self.rows.insert((node.clone(), row.key()), Kept { row, written: false });
		}
		self.held.insert(node, newest);
		newest > held
	}

	pub fn versions(&self) -> Versions {
		self.held.clone()
	}

	/// What `peer`, holding `theirs`, lacks: every node held newer here, but never `peer`'s own.
	pub fn lacking(&self, theirs: &Versions, peer: &str) -> Vec<Lack<R>> {
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

	fn held_above(&self, node: &str, above: u64) -> Vec<R> {
		self
			.rows
			.range((node.to_owned(), i64::MIN)..=(node.to_owned(), i64::MAX))
			.filter(|(_, kept)| kept.row.version() > above)
			.map(|(_, kept)| kept.row.clone())
			.collect()
	}

	/// The rows no write has taken yet.
	pub fn unwritten(&self) -> Vec<(String, R)> {
		self
			.rows
			.iter()
			.filter(|(_, kept)| !kept.written)
			.map(|((node, _), kept)| (node.clone(), kept.row.clone()))
			.collect()
	}

	/// The rows a write took, marked as written where memory still holds them at that version.
	pub fn written(&mut self, taken: &[(String, R)]) {
		for (node, row) in taken {
			if let Some(kept) = self.rows.get_mut(&(node.clone(), row.key()))
				&& kept.row.version() == row.version()
			{
				kept.written = true;
			}
		}
	}

	/// Lets go of each row written and older than `window`.
	pub fn evict(&mut self, now: Timestamp, window: Duration) {
		let old = u64::try_from(now.as_millisecond().saturating_sub(milliseconds(window))).unwrap_or(0);
		let floor = &mut self.floor;
		self.rows.retain(|(node, _), kept| {
			let going = kept.written && kept.row.version() < old;
			if going {
				let at = floor.entry(node.clone()).or_insert(0);
				*at = (*at).max(kept.row.version());
			}
			!going
		});
	}

	/// Every row held in memory, by node.
	pub fn rows(&self) -> impl Iterator<Item = (&str, &R)> {
		self.rows.iter().map(|((node, _), kept)| (node.as_str(), &kept.row))
	}
}

/// Each row by node and key, the newer version kept of two.
pub fn newest<R: Versioned>(
	rows: impl IntoIterator<Item = (String, R)>,
) -> BTreeMap<(String, i64), R> {
	let mut newest: BTreeMap<(String, i64), R> = BTreeMap::new();
	for (node, row) in rows {
		let key = (node, row.key());
		if newest.get(&key).is_none_or(|held| held.version() < row.version()) {
			newest.insert(key, row);
		}
	}
	newest
}
