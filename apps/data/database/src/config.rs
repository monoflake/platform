//! What the keeper is told by its environment: where it runs, where every core is, its place in the
//! failover order, and the passwords. Which node writes is Patroni's to decide. See
//! spec/architecture/databases.md, "Where it runs, and which one writes".

use std::collections::BTreeMap;
use std::path::PathBuf;

/// Where the cluster lives inside the container when `PGDATA` does not say.
pub const DATA: &str = "/var/lib/postgresql/data";

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
	Primary,
	Standby,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum Invalid {
	#[error("{0} is not set")]
	Missing(&'static str),
	#[error("DATABASE_PEERS holds `{0}`, which is not name=address")]
	Peer(String),
	#[error("DATABASE_PEERS gives no address for this node, {0}")]
	NoAddress(String),
	#[error("DATABASE_PRIORITY is `{0}`, not a whole number")]
	Priority(String),
	#[error("WALG_LIBSODIUM_KEY is not the 64 hex digits WALG_LIBSODIUM_KEY_TRANSFORM=hex reads")]
	Key,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
	pub node: String,
	/// Every core node's tailnet address, by name, this one's among them: Postgres, Patroni's REST
	/// and etcd are each reached there.
	pub peers: BTreeMap<String, String>,
	/// etcd's members, by address: every member of the database votes.
	pub quorum: Vec<String>,
	/// Patroni's `failover_priority`: higher is promoted first, and 0 never leads. See `ORDER` in
	/// `.mise/tasks/database`, which writes it.
	pub priority: u32,
	pub superuser_password: String,
	pub replication_password: String,
	/// What Patroni's REST asks before a switchover, a restart or a reinitialize.
	pub patroni_password: String,
	pub data: PathBuf,
}

impl Config {
	/// Read through `get`, the process environment in production and a map in tests. The backup
	/// store's settings are WAL-G's own and only checked here: nothing is archived unencrypted.
	/// See spec/architecture/databases.md, "Backups are the data, kept off the cluster".
	pub fn read(get: impl Fn(&str) -> Option<String>) -> Result<Self, Invalid> {
		let required = |key: &'static str| {
			get(key).filter(|value| !value.trim().is_empty()).ok_or(Invalid::Missing(key))
		};
		let node = required("NODE")?;
		let peers = peers(&required("DATABASE_PEERS")?)?;
		if !peers.contains_key(&node) {
			return Err(Invalid::NoAddress(node));
		}
		let priority = match get("DATABASE_PRIORITY") {
			None => 0,
			Some(text) => text.trim().parse().map_err(|_| Invalid::Priority(text))?,
		};
		let quorum = required("DATABASE_QUORUM")?.split_whitespace().map(str::to_owned).collect();
		required("WALG_S3_PREFIX")?;
		let key = required("WALG_LIBSODIUM_KEY")?;
		let hex = get("WALG_LIBSODIUM_KEY_TRANSFORM").as_deref() == Some("hex");
		if hex && (key.len() != 64 || !key.bytes().all(|b| b.is_ascii_hexdigit())) {
			return Err(Invalid::Key);
		}
		Ok(Self {
			node,
			peers,
			quorum,
			priority,
			superuser_password: required("POSTGRES_PASSWORD")?,
			replication_password: required("REPLICATION_PASSWORD")?,
			patroni_password: required("PATRONI_PASSWORD")?,
			data: get("PGDATA").map_or_else(|| PathBuf::from(DATA), PathBuf::from),
		})
	}

	/// This node's tailnet address, which `read` made sure is there.
	pub fn address(&self) -> &str {
		self.peers.get(&self.node).map_or("", String::as_str)
	}
}

/// `tyo=100.64.0.1 buf=100.64.0.2`, as `mise run database env` writes it.
fn peers(text: &str) -> Result<BTreeMap<String, String>, Invalid> {
	text
		.split_whitespace()
		.map(|pair| match pair.split_once('=') {
			Some((name, address)) if !name.is_empty() && !address.is_empty() => {
				Ok((name.to_owned(), address.to_owned()))
			}
			_ => Err(Invalid::Peer(pair.to_owned())),
		})
		.collect()
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::collections::HashMap;

	const KEY: &str = "00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff";

	fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
		let mut map: HashMap<String, String> = [
			("NODE", "buf"),
			("DATABASE_PEERS", "tyo=100.64.0.1 buf=100.64.0.2  rdu=100.64.0.3"),
			("DATABASE_QUORUM", "100.64.0.1 100.64.0.2 100.64.0.3"),
			("DATABASE_PRIORITY", "1"),
			("POSTGRES_PASSWORD", "super"),
			("REPLICATION_PASSWORD", "copy"),
			("PATRONI_PASSWORD", "rest"),
			("WALG_S3_PREFIX", "s3://bucket/database"),
			("WALG_LIBSODIUM_KEY", KEY),
			("WALG_LIBSODIUM_KEY_TRANSFORM", "hex"),
		]
		.into_iter()
		.map(|(k, v)| (k.to_owned(), v.to_owned()))
		.collect();
		for (key, value) in pairs {
			map.insert((*key).to_owned(), (*value).to_owned());
		}
		move |key| map.get(key).cloned()
	}

	#[test]
	fn reads_the_node_its_place_and_every_peer() {
		let config = Config::read(env(&[])).unwrap();
		assert_eq!(config.address(), "100.64.0.2");
		assert_eq!(config.peers.len(), 3);
		assert_eq!((config.priority, config.patroni_password.as_str()), (1, "rest"));
		assert_eq!(config.quorum, ["100.64.0.1", "100.64.0.2", "100.64.0.3"]);
		assert_eq!(config.data, PathBuf::from(DATA));
		let tyo = Config::read(env(&[("NODE", "tyo"), ("DATABASE_PRIORITY", "3")])).unwrap();
		assert_eq!((tyo.address(), tyo.priority), ("100.64.0.1", 3));
	}

	#[test]
	fn refuses_what_it_cannot_run_from() {
		let read = |pairs: &[(&str, &str)]| Config::read(env(pairs)).unwrap_err();
		assert_eq!(read(&[("NODE", "")]), Invalid::Missing("NODE"));
		assert_eq!(read(&[("DATABASE_PEERS", "tyo=1 buf")]), Invalid::Peer("buf".into()));
		assert_eq!(read(&[("NODE", "nrt")]), Invalid::NoAddress("nrt".into()));
		assert_eq!(read(&[("DATABASE_PRIORITY", "first")]), Invalid::Priority("first".into()));
		assert_eq!(read(&[("DATABASE_QUORUM", " ")]), Invalid::Missing("DATABASE_QUORUM"));
		// A member elsewhere, sha, is no core: it never leads.
		let sha = Config::read(env(&[("NODE", "buf"), ("DATABASE_PRIORITY", "0")])).unwrap();
		assert_eq!(sha.priority, 0);
		assert_eq!(read(&[("PATRONI_PASSWORD", "")]), Invalid::Missing("PATRONI_PASSWORD"));
		assert_eq!(read(&[("REPLICATION_PASSWORD", " ")]), Invalid::Missing("REPLICATION_PASSWORD"));
	}

	#[test]
	fn never_archives_without_a_key() {
		let read = |pairs: &[(&str, &str)]| Config::read(env(pairs)).unwrap_err();
		assert_eq!(read(&[("WALG_LIBSODIUM_KEY", "")]), Invalid::Missing("WALG_LIBSODIUM_KEY"));
		assert_eq!(read(&[("WALG_LIBSODIUM_KEY", "abc")]), Invalid::Key);
		assert_eq!(read(&[("WALG_S3_PREFIX", "")]), Invalid::Missing("WALG_S3_PREFIX"));
	}
}
