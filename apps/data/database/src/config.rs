//! What the keeper is told by its environment: where it runs, which node writes, where every node
//! is, and the passwords. See spec/architecture/databases.md, "Where it runs, and which one
//! writes".

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
	#[error("DATABASE_PEERS gives no address for the primary, {0}")]
	NoPrimary(String),
	#[error("WALG_LIBSODIUM_KEY is not the 64 hex digits WALG_LIBSODIUM_KEY_TRANSFORM=hex reads")]
	Key,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Config {
	pub node: String,
	pub primary: String,
	/// Every core node's tailnet address, by name.
	pub peers: BTreeMap<String, String>,
	pub superuser_password: String,
	pub replication_password: String,
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
		let primary = required("DATABASE_PRIMARY")?;
		let peers = peers(&required("DATABASE_PEERS")?)?;
		if !peers.contains_key(&primary) {
			return Err(Invalid::NoPrimary(primary));
		}
		required("WALG_S3_PREFIX")?;
		let key = required("WALG_LIBSODIUM_KEY")?;
		let hex = get("WALG_LIBSODIUM_KEY_TRANSFORM").as_deref() == Some("hex");
		if hex && (key.len() != 64 || !key.bytes().all(|b| b.is_ascii_hexdigit())) {
			return Err(Invalid::Key);
		}
		Ok(Self {
			node,
			primary,
			peers,
			superuser_password: required("POSTGRES_PASSWORD")?,
			replication_password: required("REPLICATION_PASSWORD")?,
			data: get("PGDATA").map_or_else(|| PathBuf::from(DATA), PathBuf::from),
		})
	}

	/// Primary when the configuration names this node, whatever its data says.
	pub fn role(&self) -> Role {
		if self.node == self.primary { Role::Primary } else { Role::Standby }
	}

	/// The primary's tailnet address, which `read` made sure is there.
	pub fn primary_address(&self) -> &str {
		self.peers.get(&self.primary).map_or("", String::as_str)
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
			("DATABASE_PRIMARY", "tyo"),
			("DATABASE_PEERS", "tyo=100.64.0.1 buf=100.64.0.2  rdu=100.64.0.3"),
			("POSTGRES_PASSWORD", "super"),
			("REPLICATION_PASSWORD", "copy"),
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
	fn reads_the_node_its_primary_and_every_peer() {
		let config = Config::read(env(&[])).unwrap();
		assert_eq!(config.role(), Role::Standby);
		assert_eq!(config.primary_address(), "100.64.0.1");
		assert_eq!(config.peers.len(), 3);
		assert_eq!(config.data, PathBuf::from(DATA));
		let primary = Config::read(env(&[("NODE", "tyo")])).unwrap();
		assert_eq!(primary.role(), Role::Primary);
	}

	#[test]
	fn refuses_what_it_cannot_run_from() {
		let read = |pairs: &[(&str, &str)]| Config::read(env(pairs)).unwrap_err();
		assert_eq!(read(&[("NODE", "")]), Invalid::Missing("NODE"));
		assert_eq!(read(&[("DATABASE_PEERS", "tyo=1 buf")]), Invalid::Peer("buf".into()));
		assert_eq!(read(&[("DATABASE_PRIMARY", "nrt")]), Invalid::NoPrimary("nrt".into()));
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
