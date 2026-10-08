//! What the proxy is told by its environment, as `mise run database env` writes it: the database's
//! members by tailnet address, and the ports each answers on. It needs no password: Patroni's
//! `GET /primary` asks none.

use std::net::SocketAddr;

/// Where apps reach the proxy, on every app's network: Postgres's own port, so a URL reads
/// `primary:5432`.
pub const LISTEN: u16 = 5432;
/// The port host checks `/health` on, the container's declared one. See
/// spec/architecture/services.md, "A service keeps one port".
pub const HEALTH: u16 = 15432;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Member {
	pub name: String,
	pub host: String,
	/// Patroni's REST.
	pub rest: u16,
	/// Postgres.
	pub postgres: u16,
}

impl Member {
	pub fn rest_address(&self) -> String {
		format!("{}:{}", self.host, self.rest)
	}

	pub fn postgres_address(&self) -> String {
		format!("{}:{}", self.host, self.postgres)
	}
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Invalid {
	#[error("{0} is not set")]
	Missing(&'static str),
	#[error("PRIMARY_MEMBERS holds `{0}`, which is not name=address")]
	Member(String),
	#[error("{0} is `{1}`, not a port")]
	Port(&'static str, String),
}

#[derive(Debug, Clone)]
pub struct Config {
	pub members: Vec<Member>,
	pub listen: SocketAddr,
	pub health: SocketAddr,
}

impl Config {
	/// Read through `get`, the process environment in production and a map in tests.
	pub fn read(get: impl Fn(&str) -> Option<String>) -> Result<Self, Invalid> {
		let port = |key: &'static str, default: u16| match get(key) {
			None => Ok(default),
			Some(text) => text.trim().parse().map_err(|_| Invalid::Port(key, text)),
		};
		let rest = port("PRIMARY_REST_PORT", 8008)?;
		let postgres = port("PRIMARY_POSTGRES_PORT", 5432)?;
		let text = get("PRIMARY_MEMBERS")
			.filter(|text| !text.trim().is_empty())
			.ok_or(Invalid::Missing("PRIMARY_MEMBERS"))?;
		let members = text
			.split_whitespace()
			.map(|pair| match pair.split_once('=') {
				Some((name, host)) if !name.is_empty() && !host.is_empty() => {
					Ok(Member { name: name.into(), host: host.into(), rest, postgres })
				}
				_ => Err(Invalid::Member(pair.to_owned())),
			})
			.collect::<Result<_, _>>()?;
		let any = |port| SocketAddr::from(([0, 0, 0, 0], port));
		Ok(Self { members, listen: any(LISTEN), health: any(HEALTH) })
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn reads_the_members_as_database_env_writes_them() {
		let env = |key: &str| match key {
			"PRIMARY_MEMBERS" => Some("tyo=100.64.0.1  rdu=100.64.0.3".to_owned()),
			"PRIMARY_REST_PORT" => Some("8008".to_owned()),
			_ => None,
		};
		let config = Config::read(env).unwrap();
		assert_eq!(config.members.len(), 2);
		assert_eq!(config.members[1].rest_address(), "100.64.0.3:8008");
		assert_eq!(config.members[0].postgres_address(), "100.64.0.1:5432");
		assert_eq!(config.listen.port(), 5432);
		assert_eq!(config.health.port(), 15432);
	}

	#[test]
	fn refuses_what_it_cannot_route_by() {
		let read = |members: &str, rest: &str| {
			let (members, rest) = (members.to_owned(), rest.to_owned());
			Config::read(move |key: &str| match key {
				"PRIMARY_MEMBERS" => Some(members.clone()),
				"PRIMARY_REST_PORT" => Some(rest.clone()),
				_ => None,
			})
			.unwrap_err()
		};
		assert_eq!(read(" ", "8008"), Invalid::Missing("PRIMARY_MEMBERS"));
		assert_eq!(read("tyo", "8008"), Invalid::Member("tyo".into()));
		assert_eq!(read("tyo=a", "rest"), Invalid::Port("PRIMARY_REST_PORT", "rest".into()));
	}

	#[test]
	fn the_health_port_is_the_declared_one() {
		let declared = include_str!("../service.toml");
		assert!(declared.contains(&format!("\nport = {HEALTH}\n")));
	}
}
