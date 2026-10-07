//! What a start does, from what the configuration asks and what the data directory holds. See
//! spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use crate::config::Role;
use std::path::Path;

/// What the data directory holds.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Found {
	Empty,
	Primary,
	Standby,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Plan {
	/// A first start on the primary: make the cluster.
	Initialize,
	/// A first start on a standby: copy the primary.
	Clone,
	/// The data is what the configuration says.
	Run(Role),
	/// A primary told it is a standby now, replaced while it was away: rewind it onto the new
	/// primary's history, then follow.
	Rewind,
	/// A standby told it is the primary. Promoting is the operator's command, never a start's, so it
	/// runs as the standby it is and says so.
	AwaitPromotion,
}

pub fn plan(wanted: Role, found: Found) -> Plan {
	match (wanted, found) {
		(Role::Primary, Found::Empty) => Plan::Initialize,
		(Role::Standby, Found::Empty) => Plan::Clone,
		(Role::Primary, Found::Primary) => Plan::Run(Role::Primary),
		(Role::Standby, Found::Standby) => Plan::Run(Role::Standby),
		(Role::Standby, Found::Primary) => Plan::Rewind,
		(Role::Primary, Found::Standby) => Plan::AwaitPromotion,
	}
}

#[derive(Debug, thiserror::Error)]
pub enum Unreadable {
	#[error("reading {path}: {source}")]
	Io { path: String, source: std::io::Error },
	#[error("{0} holds files but no cluster")]
	NotCluster(String),
}

/// A cluster is a standby while `standby.signal` is there; one restored and still recovering is
/// on its way to being a primary.
pub fn found(data: &Path) -> Result<Found, Unreadable> {
	let io = |source| Unreadable::Io { path: data.display().to_string(), source };
	let mut entries = match std::fs::read_dir(data) {
		Ok(entries) => entries,
		Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Found::Empty),
		Err(error) => return Err(io(error)),
	};
	if entries.next().transpose().map_err(io)?.is_none() {
		return Ok(Found::Empty);
	}
	if data.join("standby.signal").exists() {
		Ok(Found::Standby)
	} else if data.join("PG_VERSION").exists() {
		Ok(Found::Primary)
	} else {
		Err(Unreadable::NotCluster(data.display().to_string()))
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn the_configuration_and_the_data_decide_together() {
		assert_eq!(plan(Role::Primary, Found::Empty), Plan::Initialize);
		assert_eq!(plan(Role::Standby, Found::Empty), Plan::Clone);
		assert_eq!(plan(Role::Primary, Found::Primary), Plan::Run(Role::Primary));
		assert_eq!(plan(Role::Standby, Found::Standby), Plan::Run(Role::Standby));
		// A demoted primary is rewound, and a standby named primary is never promoted by a start.
		assert_eq!(plan(Role::Standby, Found::Primary), Plan::Rewind);
		assert_eq!(plan(Role::Primary, Found::Standby), Plan::AwaitPromotion);
	}

	#[test]
	fn reads_what_the_directory_holds() {
		let dir = tempfile::tempdir().unwrap();
		let data = dir.path().join("data");
		assert_eq!(found(&data).unwrap(), Found::Empty);
		std::fs::create_dir(&data).unwrap();
		assert_eq!(found(&data).unwrap(), Found::Empty);
		std::fs::write(data.join("stray"), "").unwrap();
		assert!(matches!(found(&data), Err(Unreadable::NotCluster(_))));
		std::fs::write(data.join("PG_VERSION"), "18\n").unwrap();
		assert_eq!(found(&data).unwrap(), Found::Primary);
		std::fs::write(data.join("standby.signal"), "").unwrap();
		assert_eq!(found(&data).unwrap(), Found::Standby);
	}
}
