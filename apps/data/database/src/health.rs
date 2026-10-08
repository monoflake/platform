//! What `/health` reads from Postgres and answers with, beside Patroni's view. See
//! spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use crate::config::Role;
use serde::Serialize;

/// Whether it is in recovery, and on a standby how far its replay is behind what it received.
pub const SELF: &str = "SELECT pg_is_in_recovery(), \
	coalesce((SELECT status FROM pg_stat_wal_receiver LIMIT 1), ''), \
	coalesce(pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()), 0)::bigint, \
	CASE WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() THEN 0 \
	ELSE coalesce(extract(epoch FROM now() - pg_last_xact_replay_timestamp()), 0) END::float8";

/// On the primary, each standby streaming from it and how far its replay is behind.
pub const STANDBYS: &str = "SELECT application_name, state, \
	coalesce(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn), 0)::bigint \
	FROM pg_stat_replication ORDER BY application_name";

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Status {
	/// What Postgres says it is.
	pub role: Role,
	/// What Patroni says of this member, when its REST answered.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub patroni: Option<crate::patroni::View>,
	/// On a standby: whether it streams from the primary now, rather than from the archive or not
	/// at all.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub streaming: Option<bool>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub lag_bytes: Option<i64>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub lag_seconds: Option<f64>,
	#[serde(skip_serializing_if = "Option::is_none")]
	pub standbys: Option<Vec<Standby>>,
	/// On the primary: whether backing up has stopped.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub backup: Option<crate::watch::Backup>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Standby {
	pub name: String,
	pub state: String,
	pub lag_bytes: i64,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
#[error("Postgres answered `{0}`, which is not what was asked")]
pub struct Unexpected(pub String);

/// `SELF`'s one row.
pub fn parse(row: &str) -> Result<Status, Unexpected> {
	let unexpected = || Unexpected(row.trim().to_owned());
	let fields: Vec<&str> = row.trim().split('|').collect();
	let [recovery, receiver, bytes, seconds] = fields[..] else { return Err(unexpected()) };
	let role = match recovery {
		"t" => Role::Standby,
		"f" => Role::Primary,
		_ => return Err(unexpected()),
	};
	let standby = role == Role::Standby;
	Ok(Status {
		role,
		patroni: None,
		streaming: standby.then_some(receiver == "streaming"),
		lag_bytes: if standby { Some(bytes.parse().map_err(|_| unexpected())?) } else { None },
		lag_seconds: if standby { Some(seconds.parse().map_err(|_| unexpected())?) } else { None },
		standbys: None,
		backup: None,
	})
}

/// `STANDBYS`'s rows.
pub fn standbys(rows: &str) -> Result<Vec<Standby>, Unexpected> {
	rows
		.lines()
		.filter(|line| !line.trim().is_empty())
		.map(|line| match line.split('|').collect::<Vec<_>>()[..] {
			[name, state, bytes] => Ok(Standby {
				name: name.to_owned(),
				state: state.to_owned(),
				lag_bytes: bytes.trim().parse().map_err(|_| Unexpected(line.to_owned()))?,
			}),
			_ => Err(Unexpected(line.to_owned())),
		})
		.collect()
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn reads_a_standby_and_a_primary() {
		let standby = parse("t|streaming|0|0\n").unwrap();
		assert_eq!(standby.role, Role::Standby);
		assert_eq!(standby.streaming, Some(true));
		assert_eq!(standby.lag_bytes, Some(0));

		let behind = parse("t||8192|3.25").unwrap();
		assert_eq!(behind.streaming, Some(false));
		assert_eq!(behind.lag_seconds, Some(3.25));

		let primary = parse("f||0|0").unwrap();
		assert_eq!(primary.role, Role::Primary);
		assert_eq!(primary.lag_bytes, None);
		let json = serde_json::to_value(&primary).unwrap();
		assert_eq!(json, serde_json::json!({ "role": "primary" }));
	}

	#[test]
	fn reads_the_standbys_and_refuses_garbage() {
		let rows = standbys("buf|streaming|0\nrdu|catchup|16384\n").unwrap();
		assert_eq!(rows.len(), 2);
		assert_eq!(rows[1], Standby { name: "rdu".into(), state: "catchup".into(), lag_bytes: 16384 });
		assert!(standbys("").unwrap().is_empty());
		assert!(standbys("buf|streaming").is_err());
		assert!(parse("ERROR").is_err());
	}
}
