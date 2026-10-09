//! What a relay is told by its environment: which node it is, which relays it holds a socket to,
//! the secret they share, the token that reads its own host, and where its runs' file is.

use std::collections::BTreeSet;
use std::path::PathBuf;

/// This service's port, inside its container and published on the machine. `service.toml` states
/// it for host, and a test in `main.rs` holds the two together.
pub const PORT: u16 = 12012;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Peer {
	pub name: String,
	/// `host:port` on the tailnet.
	pub address: String,
}

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum Invalid {
	#[error("`{0}` is not set")]
	Missing(&'static str),
	#[error("`{0}` in RELAY_PEERS is not `name=host:port`")]
	Peer(String),
	#[error("`{0}` is named twice in RELAY_PEERS")]
	Twice(String),
}

#[derive(Debug, Clone)]
pub struct Config {
	/// Given by host, over whatever the app's own files say.
	pub node: String,
	pub peers: Vec<Peer>,
	pub secret: String,
	pub read_token: String,
	pub listen: String,
	/// The directory `[data]` in `service.toml` mounts, or another for a run off the node.
	pub data: PathBuf,
}

impl Config {
	pub fn from_env() -> Result<Self, Invalid> {
		let required = |name: &'static str| {
			std::env::var(name).ok().filter(|value| !value.is_empty()).ok_or(Invalid::Missing(name))
		};
		let node = required("NODE")?;
		let peers = peers(&std::env::var("RELAY_PEERS").unwrap_or_default(), &node)?;
		Ok(Self {
			peers,
			secret: required("RELAY_SECRET")?,
			read_token: required("HOST_READ_TOKEN")?,
			listen: std::env::var("LISTEN").unwrap_or_else(|_| format!("0.0.0.0:{PORT}")),
			data: std::env::var("RELAY_DATA").unwrap_or_else(|_| "/data".into()).into(),
			node,
		})
	}
}

/// `name=host:port`, separated by spaces. This node's own entry is passed over, so every node can
/// be given the same list.
pub fn peers(value: &str, node: &str) -> Result<Vec<Peer>, Invalid> {
	let mut named = BTreeSet::new();
	let mut peers = Vec::new();
	for entry in value.split_whitespace() {
		let malformed = || Invalid::Peer(entry.to_owned());
		let (name, address) = entry.split_once('=').ok_or_else(malformed)?;
		let (host, port) = address.rsplit_once(':').ok_or_else(malformed)?;
		if name.is_empty() || host.is_empty() || port.parse::<u16>().is_err() {
			return Err(malformed());
		}
		if !named.insert(name) {
			return Err(Invalid::Twice(name.to_owned()));
		}
		if name != node {
			peers.push(Peer { name: name.to_owned(), address: address.to_owned() });
		}
	}
	Ok(peers)
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn peers_are_named_addresses_and_this_node_is_passed_over() {
		let peers = peers(" tyo=tyo.test:12012  rdu=rdu.test:12012\tbuf=buf.test:12012 ", "rdu");
		assert_eq!(
			peers.unwrap(),
			[
				Peer { name: "tyo".into(), address: "tyo.test:12012".into() },
				Peer { name: "buf".into(), address: "buf.test:12012".into() },
			]
		);
		assert_eq!(super::peers("", "rdu"), Ok(vec![]));
	}

	#[test]
	fn a_malformed_or_repeated_peer_is_refused() {
		for bad in ["tyo", "tyo=tyo.test", "=tyo.test:12012", "tyo=:12012", "tyo=tyo.test:http"] {
			assert_eq!(peers(bad, "rdu"), Err(Invalid::Peer(bad.into())), "{bad}");
		}
		assert_eq!(peers("tyo=a.test:1 tyo=b.test:1", "rdu"), Err(Invalid::Twice("tyo".into())));
	}
}
