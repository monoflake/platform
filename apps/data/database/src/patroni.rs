//! Patroni, the keeper's child and Postgres's parent: what its REST says of this member, and the
//! keeper's watch over it. Containers have no watchdog device, so the keeper is one: a Patroni that
//! exits, or stops answering for longer than its lease, takes Postgres down with it, so no primary
//! outlives the lease it could no longer renew. See spec/architecture/databases.md, "Where it runs,
//! and which one writes".

use bytes::Bytes;
use http_body_util::{BodyExt, Empty};
use hyper::Request;
use hyper_util::client::legacy::Client;
use hyper_util::client::legacy::connect::HttpConnector;
use hyper_util::rt::TokioExecutor;
use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant};

/// What this member's own Patroni says of it on `GET /patroni`; its other fields pass by.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct View {
	/// `running`, `starting`, `stopped`, `creating replica`, and the rest of Patroni's words.
	pub state: String,
	/// `primary`, `replica`, `standby_leader` or `uninitialized`.
	pub role: String,
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub timeline: Option<u64>,
	/// On a replica: `streaming`, or `in archive recovery`.
	#[serde(default, skip_serializing_if = "Option::is_none")]
	pub replication_state: Option<String>,
}

impl View {
	/// A member Postgres runs on, as the role it holds: what makes it healthy.
	pub fn serving(&self) -> bool {
		self.state == "running" && matches!(self.role.as_str(), "primary" | "replica")
	}
}

/// Asks this member's Patroni on its own REST, over the loopback.
pub struct Rest {
	client: Client<HttpConnector, Empty<Bytes>>,
	origin: String,
}

/// How long one question to the REST may take.
pub const PATIENCE: Duration = Duration::from_secs(3);

impl Rest {
	pub fn new(port: u16) -> Self {
		let client = Client::builder(TokioExecutor::new()).build(HttpConnector::new());
		Self { client, origin: format!("http://{}:{port}", std::net::Ipv4Addr::LOCALHOST) }
	}

	async fn get(&self, path: &str) -> Result<(u16, Bytes), String> {
		let request = Request::get(format!("{}{path}", self.origin))
			.body(Empty::new())
			.map_err(|error| error.to_string())?;
		let asked = async {
			let answer = self.client.request(request).await.map_err(|error| error.to_string())?;
			let status = answer.status().as_u16();
			let body = answer.into_body().collect().await.map_err(|error| error.to_string())?;
			Ok::<_, String>((status, body.to_bytes()))
		};
		tokio::time::timeout(PATIENCE, asked).await.map_err(|_| "Patroni did not answer".to_owned())?
	}

	/// This member as Patroni sees it; its REST answers `GET /patroni` whatever the member's state.
	pub async fn view(&self) -> Result<View, String> {
		let (_, body) = self.get("/patroni").await?;
		serde_json::from_slice(&body).map_err(|error| format!("Patroni answered unreadably: {error}"))
	}

	/// Whether Patroni's own loop is turning, as `GET /liveness` answers.
	pub async fn alive(&self) -> bool {
		matches!(self.get("/liveness").await, Ok((200, _)))
	}
}

/// The keeper's watch over Patroni: armed by its first live answer, so a start that takes long
/// is not mistaken for a hang, and fencing once no answer has been live for `limit`.
#[derive(Debug)]
pub struct Watchdog {
	limit: Duration,
	last: Option<Instant>,
}

#[derive(Debug, PartialEq, Eq)]
pub enum Verdict {
	Fine,
	/// Patroni has not answered alive for this long: Postgres is stopped before it outlives the
	/// lease.
	Fence(Duration),
}

impl Watchdog {
	pub fn new(limit: Duration) -> Self {
		Self { limit, last: None }
	}

	pub fn observe(&mut self, alive: bool, now: Instant) -> Verdict {
		if alive {
			self.last = Some(now);
			return Verdict::Fine;
		}
		match self.last {
			Some(last) if now.duration_since(last) > self.limit => {
				Verdict::Fence(now.duration_since(last))
			}
			_ => Verdict::Fine,
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn reads_a_member_as_its_rest_answers() {
		let replica = r#"{"state": "running", "postmaster_start_time": "2026-10-08 10:00:00+00:00",
			"role": "replica", "server_version": 180000, "xlog": {"received_location": 50331648},
			"timeline": 2, "replication_state": "streaming", "cluster_unlocked": false,
			"dcs_last_seen": 1791460000, "database_system_identifier": "7550000000000000000",
			"patroni": {"version": "4.1.5", "scope": "platform", "name": "rdu"}}"#;
		let view: View = serde_json::from_str(replica).unwrap();
		assert!(view.serving());
		assert_eq!(view.replication_state.as_deref(), Some("streaming"));
		let cloning: View =
			serde_json::from_str(r#"{"state": "creating replica", "role": "uninitialized"}"#).unwrap();
		assert!(!cloning.serving());
		assert_eq!(serde_json::to_value(&cloning).unwrap().get("timeline"), None);
	}

	#[test]
	fn fences_only_once_patroni_was_alive_and_then_was_not_for_longer_than_the_lease() {
		let limit = Duration::from_secs(30);
		let start = Instant::now();
		let at = |seconds| start + Duration::from_secs(seconds);
		let mut watchdog = Watchdog::new(limit);
		// Starting slowly: never alive yet, never fenced.
		assert_eq!(watchdog.observe(false, at(100)), Verdict::Fine);
		assert_eq!(watchdog.observe(true, at(101)), Verdict::Fine);
		assert_eq!(watchdog.observe(false, at(120)), Verdict::Fine);
		assert_eq!(watchdog.observe(false, at(131)), Verdict::Fine);
		assert_eq!(watchdog.observe(false, at(132)), Verdict::Fence(Duration::from_secs(31)));
		// One live answer puts it back.
		assert_eq!(watchdog.observe(true, at(133)), Verdict::Fine);
		assert_eq!(watchdog.observe(false, at(150)), Verdict::Fine);
	}
}
