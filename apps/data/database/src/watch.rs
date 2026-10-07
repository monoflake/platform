//! Whether backing up has stopped, as the primary's `/health` reports it and the backup job checks
//! it. See spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use jiff::{SignedDuration, Timestamp};
use serde::Serialize;
use std::path::Path;

/// WAL waiting longer than this to be archived means archiving has stopped. See
/// spec/architecture/databases.md, "The container is Postgres and a keeper of it".
pub const STALLED_AFTER: SignedDuration = SignedDuration::from_mins(5);
/// No base backup for longer than this means backing up has stopped; the same section.
pub const STALE_AFTER: SignedDuration = SignedDuration::from_hours(36);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Archiving {
	Ok,
	Stalled,
	/// `archive_status` could not be read.
	Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum State {
	Ok,
	Stopped,
	Unknown,
}

/// The newest base backup in the store, as far as the keeper knows.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Last {
	/// Not read from the store yet, or reading it failed.
	Unknown,
	/// The store holds no base backup.
	None,
	At(Timestamp),
}

/// The oldest segment waiting to be archived, and since when.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Waiting {
	pub segment: String,
	pub since: Timestamp,
}

/// What `/health` says of backing up, on the primary.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Backup {
	pub archiving: Archiving,
	pub oldest_waiting: Option<String>,
	pub oldest_waiting_seconds: Option<i64>,
	pub last_base_backup: Option<Timestamp>,
	pub last_base_backup_age_hours: Option<f64>,
	pub state: State,
}

/// The oldest `.ready` file of a listing of `archive_status`, each name with its modification time.
pub fn oldest_waiting(entries: impl IntoIterator<Item = (String, Timestamp)>) -> Option<Waiting> {
	entries
		.into_iter()
		.filter_map(|(name, since)| {
			name.strip_suffix(".ready").map(|segment| Waiting { segment: segment.to_owned(), since })
		})
		.min_by_key(|waiting| waiting.since)
}

/// `archive_status` in the cluster at `data`, read directly: what Postgres has finished a segment
/// of and the archive command has not yet taken.
pub fn read_waiting(data: &Path) -> std::io::Result<Option<Waiting>> {
	let mut entries = Vec::new();
	for entry in std::fs::read_dir(data.join("pg_wal/archive_status"))? {
		let entry = entry?;
		let name = entry.file_name().to_string_lossy().into_owned();
		if !name.ends_with(".ready") {
			continue;
		}
		// A file archived between the listing and this read is no longer waiting.
		let Ok(modified) = entry.metadata().and_then(|metadata| metadata.modified()) else {
			continue;
		};
		if let Ok(since) = Timestamp::try_from(modified) {
			entries.push((name, since));
		}
	}
	Ok(oldest_waiting(entries))
}

/// Whether archiving has stopped at `now`, the oldest waiting segment against `stalled_after`.
pub fn archiving(
	oldest: Option<&Waiting>,
	now: Timestamp,
	stalled_after: SignedDuration,
) -> Archiving {
	match oldest {
		Some(waiting) if now.duration_since(waiting.since) > stalled_after => Archiving::Stalled,
		_ => Archiving::Ok,
	}
}

/// Stopped when archiving has stalled or the last base backup is too old or missing; unknown while
/// either is not known; ok otherwise.
pub fn state(archiving: Archiving, last: Last, now: Timestamp) -> State {
	let stale = match last {
		Last::Unknown => None,
		Last::None => Some(true),
		Last::At(at) => Some(now.duration_since(at) > STALE_AFTER),
	};
	match (archiving, stale) {
		(Archiving::Stalled, _) | (_, Some(true)) => State::Stopped,
		(Archiving::Unknown, _) | (_, None) => State::Unknown,
		(Archiving::Ok, Some(false)) => State::Ok,
	}
}

/// The whole of what `/health` reports, from the pieces.
pub fn report(
	read: Result<Option<Waiting>, ()>,
	last: Last,
	now: Timestamp,
	stalled_after: SignedDuration,
) -> Backup {
	let (archiving, oldest) = match &read {
		Ok(oldest) => (self::archiving(oldest.as_ref(), now, stalled_after), oldest.as_ref()),
		Err(()) => (Archiving::Unknown, None),
	};
	let at = match last {
		Last::At(at) => Some(at),
		Last::Unknown | Last::None => None,
	};
	Backup {
		archiving,
		oldest_waiting: oldest.map(|waiting| waiting.segment.clone()),
		oldest_waiting_seconds: oldest.map(|waiting| now.duration_since(waiting.since).as_secs()),
		last_base_backup: at,
		last_base_backup_age_hours: at
			.map(|at| (now.duration_since(at).as_secs_f64() / 360.0).round() / 10.0),
		state: state(archiving, last, now),
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn at(seconds: i64) -> Timestamp {
		Timestamp::from_second(1_800_000_000 + seconds).unwrap()
	}

	fn listing(entries: &[(&str, i64)]) -> Vec<(String, Timestamp)> {
		entries.iter().map(|(name, seconds)| ((*name).to_owned(), at(*seconds))).collect()
	}

	#[test]
	fn the_oldest_ready_file_is_what_waits() {
		let oldest = oldest_waiting(listing(&[
			("000000010000000000000007.done", 0),
			("000000010000000000000009.ready", 200),
			("000000010000000000000008.ready", 100),
			("00000002.history.ready", 300),
		]))
		.unwrap();
		assert_eq!(oldest, Waiting { segment: "000000010000000000000008".into(), since: at(100) });
		assert_eq!(oldest_waiting(listing(&[("000000010000000000000007.done", 0)])), None);
	}

	#[test]
	fn archiving_stalls_past_the_threshold_and_not_before() {
		let waiting = Waiting { segment: "000000010000000000000008".into(), since: at(0) };
		assert_eq!(archiving(Some(&waiting), at(300), STALLED_AFTER), Archiving::Ok);
		assert_eq!(archiving(Some(&waiting), at(301), STALLED_AFTER), Archiving::Stalled);
		assert_eq!(archiving(None, at(10_000), STALLED_AFTER), Archiving::Ok);
		assert_eq!(archiving(Some(&waiting), at(2), SignedDuration::from_secs(1)), Archiving::Stalled);
	}

	#[test]
	fn state_follows_archiving_and_the_last_base_backup() {
		let day = 86_400;
		let now = at(10 * day);
		assert_eq!(state(Archiving::Ok, Last::At(at(9 * day)), now), State::Ok);
		assert_eq!(state(Archiving::Ok, Last::At(at(8 * day)), now), State::Stopped);
		assert_eq!(state(Archiving::Ok, Last::None, now), State::Stopped);
		assert_eq!(state(Archiving::Stalled, Last::At(at(10 * day)), now), State::Stopped);
		assert_eq!(state(Archiving::Stalled, Last::Unknown, now), State::Stopped);
		assert_eq!(state(Archiving::Ok, Last::Unknown, now), State::Unknown);
		assert_eq!(state(Archiving::Unknown, Last::At(at(10 * day)), now), State::Unknown);
	}

	#[test]
	fn reports_what_waits_and_how_old_the_last_backup_is() {
		let waiting = Waiting { segment: "000000010000000000000008".into(), since: at(0) };
		let report = report(Ok(Some(waiting)), Last::At(at(-5_400)), at(600), STALLED_AFTER);
		assert_eq!(report.archiving, Archiving::Stalled);
		assert_eq!(report.oldest_waiting_seconds, Some(600));
		assert_eq!(report.last_base_backup_age_hours, Some(1.7));
		assert_eq!(report.state, State::Stopped);
		let json = serde_json::to_value(super::report(Ok(None), Last::Unknown, at(0), STALLED_AFTER));
		assert_eq!(
			json.unwrap(),
			serde_json::json!({
				"archiving": "ok", "oldest_waiting": null, "oldest_waiting_seconds": null,
				"last_base_backup": null, "last_base_backup_age_hours": null, "state": "unknown",
			})
		);
	}

	#[test]
	fn reads_archive_status_from_the_cluster() {
		let dir = tempfile::tempdir().unwrap();
		let status = dir.path().join("pg_wal/archive_status");
		std::fs::create_dir_all(&status).unwrap();
		assert_eq!(read_waiting(dir.path()).unwrap(), None);
		std::fs::write(status.join("000000010000000000000003.ready"), "").unwrap();
		std::fs::write(status.join("000000010000000000000002.done"), "").unwrap();
		let waiting = read_waiting(dir.path()).unwrap().unwrap();
		assert_eq!(waiting.segment, "000000010000000000000003");
		assert!(read_waiting(&dir.path().join("missing")).is_err());
	}
}
