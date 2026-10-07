//! What the mirror job decides: whether a sync may run, what it changed, and whether the copy holds
//! what the source did. See spec/architecture/databases.md, "Backups are the data, kept off the
//! cluster".

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// Every object under a prefix, by its path below it, and its size.
pub type Listing = BTreeMap<String, u64>;

/// One entry of `rclone lsjson`.
#[derive(Deserialize)]
struct Listed {
	#[serde(rename = "Path")]
	path: String,
	/// -1 for a directory.
	#[serde(rename = "Size")]
	size: i64,
	#[serde(rename = "IsDir", default)]
	is_dir: bool,
}

pub fn listing(stdout: &str) -> Result<Listing, serde_json::Error> {
	let listed: Vec<Listed> = serde_json::from_str(stdout.trim())?;
	let files = listed.into_iter().filter(|entry| !entry.is_dir);
	Ok(files.map(|entry| (entry.path, u64::try_from(entry.size).unwrap_or(0))).collect())
}

#[derive(Debug, PartialEq, Eq, thiserror::Error)]
pub enum Refused {
	#[error("the source holds nothing under its prefix, so nothing was copied or deleted")]
	Empty,
	#[error(
		"the source holds {held} objects and the mirror {mirror}; a sync would delete more than \
		 half the mirror, which the tiers never do in a day, so nothing was copied or deleted"
	)]
	Halved { held: usize, mirror: usize },
}

/// Whether a sync may run: never from an empty source, nor one holding less than half of what the
/// mirror does. An unreadable source never reaches here.
pub fn guard(source: &Listing, mirror: &Listing) -> Result<(), Refused> {
	if source.is_empty() {
		return Err(Refused::Empty);
	}
	if source.len() * 2 < mirror.len() {
		return Err(Refused::Halved { held: source.len(), mirror: mirror.len() });
	}
	Ok(())
}

/// The source's objects the mirror lacks after a sync, or holds at another size, at most `shown`
/// of them named.
pub fn missing(source: &Listing, mirror: &Listing, shown: usize) -> (usize, Vec<String>) {
	let lacking: Vec<&String> =
		source.iter().filter(|(path, size)| mirror.get(*path) != Some(size)).map(|(p, _)| p).collect();
	(lacking.len(), lacking.into_iter().take(shown).cloned().collect())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize)]
pub struct Held {
	pub objects: usize,
	pub bytes: u64,
}

impl Held {
	pub fn of(listing: &Listing) -> Self {
		Self { objects: listing.len(), bytes: listing.values().sum() }
	}
}

/// What one run did, from the listings either side of it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Report {
	pub source: Held,
	/// Objects the mirror lacked or held at another size, copied.
	pub copied: usize,
	/// Objects the mirror held and the source no longer does, deleted.
	pub deleted: usize,
	pub mirror: Held,
}

impl Report {
	pub fn new(source: &Listing, before: &Listing, after: &Listing) -> Self {
		Self {
			source: Held::of(source),
			copied: missing(source, before, 0).0,
			deleted: before.keys().filter(|path| !source.contains_key(*path)).count(),
			mirror: Held::of(after),
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn list(entries: &[(&str, u64)]) -> Listing {
		entries.iter().map(|(path, size)| ((*path).to_owned(), *size)).collect()
	}

	#[test]
	fn reads_rclone_listing_and_passes_over_directories() {
		let out = r#"[
			{"Path":"basebackups_005","Name":"basebackups_005","Size":-1,"IsDir":true},
			{"Path":"wal_005/000000010000000000000003.br","Name":"000000010000000000000003.br","Size":65536,"IsDir":false},
			{"Path":"basebackups_005/base_000000010000000000000004_backup_stop_sentinel.json","Name":"x","Size":812}
		]"#;
		let listed = listing(out).unwrap();
		assert_eq!(listed.len(), 2);
		assert_eq!(listed["wal_005/000000010000000000000003.br"], 65536);
		assert!(listing("[]").unwrap().is_empty());
	}

	#[test]
	fn never_syncs_from_nothing_or_from_less_than_half() {
		let mirror = list(&[("a", 1), ("b", 1), ("c", 1), ("d", 1), ("e", 1)]);
		assert_eq!(guard(&Listing::new(), &mirror), Err(Refused::Empty));
		assert_eq!(guard(&Listing::new(), &Listing::new()), Err(Refused::Empty));
		let two = list(&[("a", 1), ("b", 1)]);
		assert_eq!(guard(&two, &mirror), Err(Refused::Halved { held: 2, mirror: 5 }));
		let three = list(&[("a", 1), ("b", 1), ("f", 1)]);
		assert_eq!(guard(&three, &mirror), Ok(()));
		// A first run, into an empty mirror.
		assert_eq!(guard(&two, &Listing::new()), Ok(()));
	}

	#[test]
	fn reports_what_a_sync_changed_and_what_it_left_out() {
		let source = list(&[("wal/1", 10), ("wal/2", 10), ("base/meta.json", 30)]);
		let before = list(&[("wal/0", 10), ("wal/1", 10), ("base/meta.json", 29)]);
		let after = source.clone();
		let report = Report::new(&source, &before, &after);
		assert_eq!(report.copied, 2, "wal/2 new, meta.json rewritten");
		assert_eq!(report.deleted, 1, "wal/0 let go by the tiers");
		assert_eq!(report.source, Held { objects: 3, bytes: 50 });
		assert_eq!(report.mirror, Held { objects: 3, bytes: 50 });
		assert_eq!(missing(&source, &after, 5), (0, vec![]));
		assert_eq!(missing(&source, &before, 1), (2, vec!["base/meta.json".to_owned()]));
	}
}
