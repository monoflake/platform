//! The daily base backup and what is kept of the ones before it. See
//! spec/architecture/databases.md, "Backups are the data, kept off the cluster".

use jiff::tz::TimeZone;
use jiff::{SignedDuration, Timestamp};
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet};

/// How a tier chooses among the backups in it: each UTC calendar day, ISO week, month or half
/// year keeps its oldest backup, and the first tier keeps every one.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Bucket {
	Every,
	Day,
	Week,
	Month,
	HalfYear,
}

/// Each tier as the age in days it reaches to and how it chooses; past the last, nothing is kept.
/// See spec/architecture/databases.md, "Backups are the data, kept off the cluster".
pub const TIERS: [(i64, Bucket); 5] = [
	(7, Bucket::Every),
	(30, Bucket::Day),
	(91, Bucket::Week),
	(365, Bucket::Month),
	(3 * 365 + 1, Bucket::HalfYear),
];

/// One base backup as `wal-g backup-list --detail --json` lists it.
#[derive(Debug, Clone, PartialEq, Deserialize)]
pub struct Listed {
	pub backup_name: String,
	pub start_time: Timestamp,
	#[serde(default)]
	pub is_permanent: bool,
}

/// `wal-g backup-list --detail --json`'s answer; nothing at all when there is no backup yet.
pub fn listed(stdout: &str) -> Result<Vec<Listed>, serde_json::Error> {
	if stdout.trim().is_empty() { Ok(Vec::new()) } else { serde_json::from_str(stdout) }
}

/// What one backup job does to the store after its own backup is pushed.
#[derive(Debug, Default, PartialEq, Eq)]
pub struct Changes {
	pub mark: Vec<String>,
	pub unmark: Vec<String>,
	/// Every backup not permanent before this one goes, and every WAL segment no permanent backup
	/// needs for itself.
	pub delete_before: Option<String>,
}

fn days(days: i64) -> SignedDuration {
	SignedDuration::from_hours(days * 24)
}

/// The calendar bucket an instant falls in when chosen by `choice`, by UTC.
fn key(choice: Bucket, at: Timestamp) -> i64 {
	let date = at.to_zoned(TimeZone::UTC).date();
	let (year, month) = (i64::from(date.year()), i64::from(date.month()));
	match choice {
		Bucket::Every => 0,
		Bucket::Day => year * 10_000 + month * 100 + i64::from(date.day()),
		Bucket::Week => {
			let week = date.iso_week_date();
			i64::from(week.year()) * 100 + i64::from(week.week())
		}
		Bucket::Month => year * 100 + month,
		Bucket::HalfYear => year * 10 + i64::from(month > 6),
	}
}

/// The ages a tier covers: past the one before it, up to its own reach.
fn span(tier: usize) -> (SignedDuration, SignedDuration) {
	let floor = if tier == 0 { SignedDuration::MIN } else { days(TIERS[tier - 1].0) };
	(floor, days(TIERS[tier].0))
}

/// The backups the tiers keep, at `now`. Each bucket a tier's span touches keeps its oldest backup
/// left, whichever tier that one is in: oldest, because backups age into a tier oldest first, so
/// the one kept is the first to arrive and stays kept, where the newest would move each day. A
/// bucket straddling a tier's edge is so never left without one.
pub fn kept(backups: &[Listed], now: Timestamp) -> BTreeSet<&str> {
	let age = |backup: &Listed| now.duration_since(backup.start_time);
	let last = days(TIERS[TIERS.len() - 1].0);
	let mut kept = BTreeSet::new();
	for (tier, &(_, choice)) in TIERS.iter().enumerate() {
		let (floor, reach) = span(tier);
		// Every bucket the tier's span of time touches, whether or not a backup in it is left.
		let newest = if tier == 0 { now } else { now - floor };
		let covered: BTreeSet<i64> = (0..=TIERS[tier].0)
			.map(|day| (now - reach + days(day)).min(newest))
			.map(|at| key(choice, at))
			.collect();
		let mut oldest: BTreeMap<i64, &Listed> = BTreeMap::new();
		for backup in backups.iter().filter(|backup| age(backup) <= last) {
			let bucket = key(choice, backup.start_time);
			if !covered.contains(&bucket) {
				continue;
			}
			if choice == Bucket::Every {
				if age(backup) <= reach {
					kept.insert(backup.backup_name.as_str());
				}
				continue;
			}
			let held = oldest.entry(bucket).or_insert(backup);
			if backup.start_time < held.start_time {
				*held = backup;
			}
		}
		kept.extend(oldest.values().map(|backup| backup.backup_name.as_str()));
	}
	kept
}

/// What to mark, unmark and delete before at `now`. Kept and older than the first tier is
/// permanent, which keeps the backup and its own WAL through every delete. Everything else goes
/// once it is older than the newest backup started before the first tier's reach, from which every
/// second since is restored.
pub fn changes(backups: &[Listed], now: Timestamp) -> Changes {
	let reach = now - SignedDuration::from_hours(TIERS[0].0 * 24);
	let kept = kept(backups, now);
	let permanent =
		|backup: &&Listed| kept.contains(backup.backup_name.as_str()) && backup.start_time < reach;
	let name = |backup: &Listed| backup.backup_name.clone();
	let anchor = backups
		.iter()
		.filter(|backup| backup.start_time <= reach)
		.max_by_key(|backup| backup.start_time);
	let older = |anchor: &Listed| backups.iter().any(|b| b.start_time < anchor.start_time);
	Changes {
		mark: backups.iter().filter(|b| permanent(b) && !b.is_permanent).map(name).collect(),
		unmark: backups.iter().filter(|b| !permanent(b) && b.is_permanent).map(name).collect(),
		delete_before: anchor.filter(|anchor| older(anchor)).map(name),
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn at(day: i64) -> Timestamp {
		Timestamp::from_second(day * 86_400 + 3_600).unwrap()
	}

	fn daily(from: i64, to: i64) -> Vec<Listed> {
		(from..=to)
			.map(|day| Listed {
				backup_name: format!("base_{day}"),
				start_time: at(day),
				is_permanent: false,
			})
			.collect()
	}

	/// Applies `changes` as WAL-G would: marks, unmarks, then deletes what is before the anchor and
	/// not permanent.
	fn apply(backups: &mut Vec<Listed>, changes: &Changes) {
		for backup in backups.iter_mut() {
			if changes.mark.contains(&backup.backup_name) {
				backup.is_permanent = true;
			}
			if changes.unmark.contains(&backup.backup_name) {
				backup.is_permanent = false;
			}
		}
		if let Some(anchor) = &changes.delete_before {
			let at = backups.iter().find(|b| &b.backup_name == anchor).unwrap().start_time;
			backups.retain(|b| b.is_permanent || b.start_time >= at);
		}
	}

	/// A backup each day for `days`, the job run after each, as the node would.
	fn run(days: i64) -> Vec<Listed> {
		let mut backups = Vec::new();
		for day in 0..days {
			backups.extend(daily(day, day));
			let changes = changes(&backups, at(day));
			apply(&mut backups, &changes);
		}
		backups
	}

	fn ages(backups: &[Listed], now: Timestamp) -> Vec<i64> {
		backups.iter().map(|b| now.duration_since(b.start_time).as_hours() / 24).collect()
	}

	#[test]
	fn four_years_of_daily_backups_thin_into_the_tiers() {
		let days = 4 * 365;
		let backups = run(days);
		let now = at(days - 1);
		let ages = ages(&backups, now);
		let count = |from: i64, to: i64| ages.iter().filter(|age| (from..=to).contains(*age)).count();
		assert_eq!(count(0, 7), 8, "every day of the last week, and the one it restores from");
		assert_eq!(count(8, 30), 23, "each day's");
		assert!((8..=10).contains(&count(31, 91)), "one a week: {}", count(31, 91));
		assert!((8..=10).contains(&count(92, 365)), "one a month: {}", count(92, 365));
		assert!((3..=5).contains(&count(366, 3 * 365 + 1)), "one a half year: {}", count(366, 1096));
		assert_eq!(count(3 * 365 + 2, i64::MAX), 0, "nothing past three years");
		// Everything older than the reach of the first tier is permanent, and nothing in it is.
		assert!(
			backups.iter().all(|b| b.is_permanent
				== (now.duration_since(b.start_time) > SignedDuration::from_hours(7 * 24)))
		);
	}

	#[test]
	fn every_bucket_that_had_a_backup_still_has_one() {
		// Every day of two years, each the job's now: a bucket a tier covers is never left empty,
		// its edges with the tiers either side included.
		let mut backups = Vec::new();
		for day in 0..2 * 365 {
			backups.extend(daily(day, day));
			let now = at(day);
			let changes = changes(&backups, now);
			apply(&mut backups, &changes);
			let all = daily(0, day);
			for (tier, &(_, choice)) in TIERS.iter().enumerate() {
				let (floor, reach) = span(tier);
				let age = |b: &Listed| now.duration_since(b.start_time);
				let keys = |list: &[Listed], lower, upper| -> BTreeSet<i64> {
					list
						.iter()
						.filter(|b| age(b) > lower && age(b) <= upper)
						.map(|b| key(choice, b.start_time))
						.collect()
				};
				let had: BTreeSet<i64> = keys(&all, floor, reach);
				let has = keys(&backups, SignedDuration::MIN, days(TIERS[TIERS.len() - 1].0));
				assert!(had.is_subset(&has), "day {day}, tier {tier}: {had:?} against {has:?}");
			}
		}
	}

	#[test]
	fn the_oldest_of_a_bucket_is_kept_and_stays_kept() {
		// Days 0 to 13 are 1970's Thursday the 1st to Wednesday the 14th, in ISO weeks 1 (to Sunday
		// the 4th), 2 and 3. At day 60 they are in the weekly tier.
		let backups = daily(0, 13);
		let kept = kept(&backups, at(60));
		assert_eq!(kept, BTreeSet::from(["base_0", "base_4", "base_11"]));
		let later = super::kept(&backups, at(61));
		assert_eq!(kept, later);
	}

	#[test]
	fn restores_every_second_of_the_last_week() {
		let backups = daily(0, 20);
		let changes = changes(&backups, at(20) + SignedDuration::from_hours(12));
		// The reach is day 13.5, which day 13's backup and the WAL after it restore.
		assert_eq!(changes.delete_before.as_deref(), Some("base_13"));
		assert_eq!(changes.mark.len(), 14, "days 0 to 13, each its day's");
		assert!(changes.unmark.is_empty());
	}

	#[test]
	fn deletes_nothing_while_everything_is_in_the_first_tier() {
		let backups = daily(5, 10);
		assert_eq!(changes(&backups, at(10)), Changes::default());
		assert_eq!(changes(&[], at(10)), Changes::default());
	}

	#[test]
	fn unmarks_what_the_tiers_no_longer_keep() {
		let mut backups = daily(0, 1);
		backups[1].is_permanent = true;
		// At day 60 both are in one ISO week, and the oldest, day 0, is the one kept.
		let changes = changes(&backups, at(60));
		assert_eq!(changes.mark, vec!["base_0".to_owned()]);
		assert_eq!(changes.unmark, vec!["base_1".to_owned()]);
	}

	#[test]
	fn reads_wal_g_listing() {
		let json = r#"[{"backup_name":"base_000000010000000000000004","time":"2026-10-07T10:00:05Z",
			"wal_file_name":"000000010000000000000004","start_time":"2026-10-07T10:00:01.5Z",
			"finish_time":"2026-10-07T10:00:04Z","hostname":"tyo","is_permanent":true}]"#;
		let backups = listed(json).unwrap();
		assert_eq!(backups[0].backup_name, "base_000000010000000000000004");
		assert_eq!(backups[0].start_time.to_string(), "2026-10-07T10:00:01.5Z");
		assert!(backups[0].is_permanent);
		assert!(listed("\n").unwrap().is_empty());
	}
}
