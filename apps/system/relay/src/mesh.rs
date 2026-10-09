//! The relays' mesh: a socket to every other node's relay. Both ends open with the versions they
//! hold and send each other what the other lacks; after that a relay sends its own node's snapshot
//! the moment it changes, and every other node's when a neighbor's comparison shows it behind. Its
//! pings, timed, are the round trips its own snapshot carries. The runs travel the same way, by
//! their own versions. See spec/architecture/relay.md.

use crate::cluster::{Carried, Versions};
use crate::config::Peer;
use crate::relay::{Relay, Update, VERSION};
use crate::runs::Batch;
use crate::socket::{Dial, Received, Socket, SocketError};
use axum::http::HeaderMap;
use axum::http::header::{AUTHORIZATION, InvalidHeaderValue};
use bytes::Bytes;
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::broadcast::error::RecvError;
use tokio::time::Instant;
use tokio_tungstenite::tungstenite;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;

/// Where a relay accepts its neighbors.
pub const PATH: &str = "/mesh";

/// How often a relay tells a neighbor what it holds, and so the most a snapshot waits at each hop
/// past its own node. Passing every snapshot on at once would send each one over every socket of a
/// full mesh, every round, since the machine's sample changes every round.
pub const COMPARISON: Duration = Duration::from_secs(2);

/// Cloudflare and NATs close a socket idle for long; a ping keeps it from looking idle. A browser's
/// socket is pinged this often; a neighbor's, every `PING`.
pub const HEARTBEAT: Duration = Duration::from_secs(30);

/// How often a relay pings each neighbor and times the pong, the first ping as the socket opens.
/// Its own snapshot is taken every `own::EVERY`, so a faster ping times a figure no round carries;
/// a slower one leaves the figure a round behind. Two ten-byte frames a socket, beside snapshots of
/// kilobytes every round. See spec/architecture/relay.md, "The round trip to each neighbor".
pub const PING: Duration = crate::own::EVERY;

/// A neighbor that has sent nothing, not even a pong, for ninety seconds is gone.
const SILENCE: Duration = Duration::from_secs(90);

/// How long the other end has to say who it is.
const INTRODUCTION: Duration = Duration::from_secs(10);

const FIRST_RETRY: Duration = Duration::from_secs(1);
const LAST_RETRY: Duration = Duration::from_secs(60);

/// What one relay sends another. `runs` is absent from a relay older than the runs, which is
/// never sent `Runs`, a kind it cannot read; so the contract's version stands.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Message {
	/// Sent first by both ends: the contract's version, who it is, and what it holds.
	Hello {
		version: u32,
		node: String,
		versions: Versions,
		#[serde(default, skip_serializing_if = "Option::is_none")]
		runs: Option<Versions>,
	},
	/// What it holds, every comparison; answered with what it lacks.
	Versions {
		versions: Versions,
		#[serde(default, skip_serializing_if = "Option::is_none")]
		runs: Option<Versions>,
	},
	/// A node's snapshot, newer than what the other was last known to hold.
	Node { node: String, state: Carried },
	/// Some of a node's runs, which the other was last known to lack.
	Runs(Batch),
}

#[derive(Debug, thiserror::Error)]
pub enum MeshError {
	#[error(transparent)]
	Socket(#[from] SocketError),
	#[error("dialing: {0}")]
	Dial(#[from] tungstenite::Error),
	#[error("no answer within {0:?}")]
	Slow(Duration),
	#[error("a message this relay cannot read: {0}")]
	Malformed(#[from] serde_json::Error),
	#[error("it speaks version {0} of the mesh")]
	Version(u32),
	#[error("it opened with something other than hello")]
	Unintroduced,
	#[error("it says it is `{0}`")]
	Stranger(String),
	#[error("nothing heard for {0:?}")]
	Silent(Duration),
	#[error("it closed the socket")]
	Closed,
}

/// Whether a request carries the mesh's secret, compared in time independent of where the first
/// difference is.
pub fn admitted(headers: &HeaderMap, secret: &str) -> bool {
	let given = headers
		.get(AUTHORIZATION)
		.and_then(|value| value.to_str().ok())
		.and_then(|value| value.strip_prefix("Bearer "))
		.unwrap_or_default();
	!secret.is_empty()
		&& given.len() == secret.len()
		&& given.bytes().zip(secret.bytes()).fold(0, |acc, (a, b)| acc | (a ^ b)) == 0
}

/// One of the sockets to a neighbor -- two relays that each dial the other hold two. Only the first
/// open sends unasked, so nothing goes twice; the other takes over when it closes.
struct Speaking<'a> {
	relay: &'a Relay,
	peer: &'a str,
	conversation: u64,
}

impl Speaking<'_> {
	fn speaks(&self) -> bool {
		self.relay.speaks(self.peer, self.conversation)
	}
}

impl Drop for Speaking<'_> {
	fn drop(&mut self) {
		self.relay.hush(self.peer, self.conversation);
	}
}

/// One socket to a neighbor, from the introductions until it closes. `expected` is the neighbor
/// dialed, and none for one that dialed here.
pub async fn converse<S: Socket>(
	relay: Arc<Relay>,
	expected: Option<&str>,
	mut socket: S,
) -> Result<(), MeshError> {
	// Subscribed before saying what is held, so nothing taken meanwhile is missed.
	let mut updates = relay.subscribe();
	let mut batches = relay.subscribe_runs();
	let hello = Message::Hello {
		version: VERSION,
		node: relay.node().to_owned(),
		versions: relay.versions(),
		runs: Some(relay.run_versions()),
	};
	send(&mut socket, &hello).await?;

	let theirs = tokio::time::timeout(INTRODUCTION, introduced(&mut socket))
		.await
		.map_err(|_| MeshError::Slow(INTRODUCTION))??;
	let (peer, versions, runs) = match theirs {
		Message::Hello { version, .. } if version != VERSION => {
			return Err(MeshError::Version(version));
		}
		Message::Hello { node, versions, runs, .. } => (node, versions, runs),
		Message::Versions { .. } | Message::Node { .. } | Message::Runs(_) => {
			return Err(MeshError::Unintroduced);
		}
	};
	if peer == relay.node() || expected.is_some_and(|expected| expected != peer) {
		return Err(MeshError::Stranger(peer));
	}
	// A neighbor that said nothing of runs is older than them; see `Message`.
	let reads_runs = runs.is_some();
	behind(&relay, &mut socket, &versions, &peer).await?;
	if let Some(runs) = runs {
		runs_behind(&relay, &mut socket, &runs, &peer).await?;
	}

	let speaking = Speaking { relay: &relay, peer: &peer, conversation: relay.conversation() };
	let mut comparison = tokio::time::interval_at(Instant::now() + COMPARISON, COMPARISON);
	let mut ping = tokio::time::interval(PING);
	let origin = Instant::now();
	let mut heard = Instant::now();
	loop {
		tokio::select! {
			received = socket.receive() => {
				heard = Instant::now();
				match received? {
					Received::Text(text) => match serde_json::from_str(&text)? {
						Message::Node { node, state } => {
							relay.take(&node, state, Some(&peer));
						}
						Message::Versions { versions, runs } => {
							behind(&relay, &mut socket, &versions, &peer).await?;
							if let Some(runs) = runs {
								runs_behind(&relay, &mut socket, &runs, &peer).await?;
							}
						}
						Message::Runs(batch) => {
							relay.take_runs(batch);
						}
						Message::Hello { .. } => {}
					},
					Received::Pong(payload) => {
						if let Some(round_trip) = round_trip(origin, &payload, Instant::now()) {
							relay.timed(&peer, round_trip);
						}
					}
					Received::Closed => return Ok(()),
					Received::Other => {}
				}
			}
			update = updates.recv() => match update {
				Ok(Update { node, held }) => {
					if node == relay.node() && speaking.speaks() {
						let state = Carried { version: held.version, snapshot: held.snapshot };
						send(&mut socket, &Message::Node { node, state }).await?;
						relay.told(&peer, held.version);
					}
				}
				// What it missed, the next comparison finds.
				Err(RecvError::Lagged(_)) => {}
				Err(RecvError::Closed) => return Ok(()),
			},
			batch = batches.recv() => match batch {
				Ok(batch) => {
					if batch.node == relay.node() && reads_runs && speaking.speaks() {
						send(&mut socket, &Message::Runs(batch)).await?;
					}
				}
				Err(RecvError::Lagged(_)) => {}
				Err(RecvError::Closed) => return Ok(()),
			},
			_ = comparison.tick() => {
				if speaking.speaks() {
					let runs = Some(relay.run_versions());
					send(&mut socket, &Message::Versions { versions: relay.versions(), runs }).await?;
				}
			}
			_ = ping.tick() => {
				if heard.elapsed() >= SILENCE {
					return Err(MeshError::Silent(SILENCE));
				}
				socket.ping(stamp(origin, Instant::now())).await?;
			}
		}
	}
}

/// A ping's payload: when it was sent, in microseconds since the socket's `origin`. The pong
/// carries it back, so nothing is kept per ping, and a pong later than the next ping still times
/// its own.
fn stamp(origin: Instant, now: Instant) -> Bytes {
	let sent = u64::try_from(now.duration_since(origin).as_micros()).unwrap_or(u64::MAX);
	Bytes::copy_from_slice(&sent.to_be_bytes())
}

/// The round trip a pong closes, or none for a pong to no ping of this socket's: another shape, or
/// sent later than `now`.
fn round_trip(origin: Instant, payload: &[u8], now: Instant) -> Option<Duration> {
	let sent = u64::from_be_bytes(payload.try_into().ok()?);
	let elapsed = now.duration_since(origin);
	elapsed.checked_sub(Duration::from_micros(sent))
}

/// Sends `peer`, holding `versions`, what it lacks.
async fn behind<S: Socket>(
	relay: &Relay,
	socket: &mut S,
	versions: &Versions,
	peer: &str,
) -> Result<(), MeshError> {
	for (node, state) in relay.lacking(versions, peer) {
		let own = (node == relay.node()).then_some(state.version);
		send(socket, &Message::Node { node, state }).await?;
		if let Some(version) = own {
			relay.told(peer, version);
		}
	}
	Ok(())
}

/// Sends `peer`, holding `theirs` of the runs, what it lacks. A file that cannot be read is
/// logged, and asked again at the next comparison; the socket stays.
async fn runs_behind<S: Socket>(
	relay: &Relay,
	socket: &mut S,
	theirs: &Versions,
	peer: &str,
) -> Result<(), MeshError> {
	match relay.lacking_runs(theirs, peer).await {
		Ok(batches) => {
			for batch in batches {
				send(socket, &Message::Runs(batch)).await?;
			}
		}
		Err(error) => eprintln!("relay: reading the runs for {peer}: {error}"),
	}
	Ok(())
}

async fn introduced<S: Socket>(socket: &mut S) -> Result<Message, MeshError> {
	loop {
		match socket.receive().await? {
			Received::Text(text) => return Ok(serde_json::from_str(&text)?),
			Received::Closed => return Err(MeshError::Closed),
			Received::Pong(_) | Received::Other => {}
		}
	}
}

async fn send<S: Socket>(socket: &mut S, message: &Message) -> Result<(), MeshError> {
	Ok(socket.send_text(serde_json::to_string(message)?).await?)
}

/// Opens a socket to `peer`'s relay, carrying the secret.
pub async fn dial(peer: &Peer, secret: &str) -> Result<Dial, MeshError> {
	let mut request = format!("ws://{}{PATH}", peer.address).into_client_request()?;
	let bearer = format!("Bearer {secret}")
		.parse()
		.map_err(|error: InvalidHeaderValue| tungstenite::Error::HttpFormat(error.into()))?;
	request.headers_mut().insert(AUTHORIZATION, bearer);
	let dialing = tokio_tungstenite::connect_async(request);
	let (socket, _) = tokio::time::timeout(INTRODUCTION, dialing)
		.await
		.map_err(|_| MeshError::Slow(INTRODUCTION))??;
	Ok(socket)
}

/// Holds a socket to `peer` for as long as the relay runs, dialing again after each loss, waiting
/// twice as long each time it fails up to a minute. A neighbor down waits alone.
pub async fn keep(relay: Arc<Relay>, peer: Peer) {
	let mut wait = FIRST_RETRY;
	loop {
		match dial(&peer, relay.secret()).await {
			Ok(socket) => {
				eprintln!("relay: holding {}", peer.name);
				let opened = Instant::now();
				let ended = converse(relay.clone(), Some(&peer.name), socket).await;
				match ended {
					Ok(()) => eprintln!("relay: {} closed", peer.name),
					Err(error) => eprintln!("relay: lost {}: {error}", peer.name),
				}
				if opened.elapsed() >= LAST_RETRY {
					wait = FIRST_RETRY;
				}
			}
			Err(error) => eprintln!("relay: dialing {} at {}: {error}", peer.name, peer.address),
		}
		tokio::time::sleep(wait).await;
		wait = (wait * 2).min(LAST_RETRY);
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use axum::http::HeaderValue;
	use std::sync::Mutex;
	use tokio::sync::mpsc;

	fn relay(node: &str) -> Arc<Relay> {
		Relay::new(
			node.into(),
			"s3cret".into(),
			Default::default(),
			crate::runs::Store::memory().unwrap(),
		)
		.unwrap()
	}

	/// A socket whose other end is the test: what it is fed, it receives, and what it sends is kept.
	/// Given an `echo`, it answers its own pings, as the other end's socket does beneath.
	struct Fake {
		incoming: mpsc::UnboundedReceiver<Received>,
		sent: Arc<Mutex<Vec<Message>>>,
		echo: Option<mpsc::UnboundedSender<Received>>,
	}

	impl Socket for Fake {
		async fn send_text(&mut self, text: String) -> Result<(), SocketError> {
			self.sent.lock().unwrap().push(serde_json::from_str(&text).unwrap());
			Ok(())
		}

		async fn ping(&mut self, payload: Bytes) -> Result<(), SocketError> {
			if let Some(echo) = &self.echo {
				let _ = echo.send(Received::Pong(payload));
			}
			Ok(())
		}

		async fn receive(&mut self) -> Result<Received, SocketError> {
			Ok(self.incoming.recv().await.unwrap_or(Received::Closed))
		}
	}

	#[tokio::test]
	async fn meeting_sends_hello_and_then_exactly_what_the_other_lacks() {
		let relay = relay("rdu");
		let snapshot = Arc::new(serde_json::json!({}));
		for (node, version) in [("rdu", 9), ("tyo", 4), ("buf", 7), ("gvx", 2)] {
			relay.take(node, Carried { version, snapshot: snapshot.clone() }, None);
		}
		let (feed, incoming) = mpsc::unbounded_channel();
		let sent = Arc::new(Mutex::new(Vec::new()));
		let theirs = Versions::from([("tyo".into(), 6), ("buf".into(), 7), ("gvx".into(), 1)]);
		let hello =
			Message::Hello { version: VERSION, node: "tyo".into(), versions: theirs, runs: None };
		feed.send(Received::Text(serde_json::to_string(&hello).unwrap())).unwrap();
		drop(feed);

		converse(relay.clone(), Some("tyo"), Fake { incoming, sent: sent.clone(), echo: None })
			.await
			.unwrap();
		let sent = sent.lock().unwrap();
		assert!(matches!(&sent[0], Message::Hello { node, versions, .. }
			if node == "rdu" && *versions == relay.versions()));
		// Not tyo's own, however old it is here, and not buf, which it holds as new.
		let nodes: Vec<(&str, u64)> = sent[1..]
			.iter()
			.map(|message| match message {
				Message::Node { node, state } => (node.as_str(), state.version),
				other => panic!("sent {other:?}"),
			})
			.collect();
		assert_eq!(nodes, [("gvx", 2), ("rdu", 9)]);
	}

	/// tyo's hello, holding `runs` of the runs or older than them.
	async fn met(relay: &Arc<Relay>, runs: Option<Versions>) -> Vec<Message> {
		let (feed, incoming) = mpsc::unbounded_channel();
		let sent = Arc::new(Mutex::new(Vec::new()));
		let hello =
			Message::Hello { version: VERSION, node: "tyo".into(), versions: Versions::new(), runs };
		feed.send(Received::Text(serde_json::to_string(&hello).unwrap())).unwrap();
		drop(feed);
		converse(relay.clone(), Some("tyo"), Fake { incoming, sent: sent.clone(), echo: None })
			.await
			.unwrap();
		sent.lock().unwrap().clone()
	}

	#[tokio::test]
	async fn a_neighbor_is_sent_the_runs_it_lacks_and_one_older_than_runs_none() {
		let relay = relay("rdu");
		let row = |id: i64, version: u64| crate::runs::Row {
			version,
			event: crate::host::Event {
				id,
				app: "geo".into(),
				action: "deploy".into(),
				source: crate::host::Source { kind: "panel".into(), run: None, commit: None },
				image: None,
				outcome: "succeeded".into(),
				stage: None,
				detail: None,
				started_at: jiff::Timestamp::now().to_string(),
				finished_at: None,
			},
		};
		for (node, version) in [("buf", 7), ("tyo", 4)] {
			relay.take_runs(Batch { node: node.into(), above: 0, version, rows: vec![row(1, version)] });
		}

		let runs: Vec<(String, u64, usize)> = met(&relay, Some(Versions::from([("buf".into(), 3)])))
			.await
			.into_iter()
			.filter_map(|message| match message {
				Message::Runs(batch) => Some((batch.node, batch.above, batch.rows.len())),
				_ => None,
			})
			.collect();
		// buf above what tyo holds of it, and never tyo's own.
		assert_eq!(runs, [("buf".into(), 3, 1)]);

		let older = met(&relay, None).await;
		assert!(matches!(&older[0], Message::Hello { runs: Some(_), .. }));
		assert!(!older.iter().any(|message| matches!(message, Message::Runs(_))));
	}

	#[tokio::test]
	async fn a_neighbor_that_is_not_the_one_dialed_is_refused() {
		let relay = relay("rdu");
		for (said, expected) in [("buf", Some("tyo")), ("rdu", None)] {
			let (feed, incoming) = mpsc::unbounded_channel();
			let hello = Message::Hello {
				version: VERSION,
				node: said.into(),
				versions: Versions::new(),
				runs: None,
			};
			feed.send(Received::Text(serde_json::to_string(&hello).unwrap())).unwrap();
			let fake = Fake { incoming, sent: Arc::default(), echo: None };
			let refused = converse(relay.clone(), expected, fake).await;
			assert!(matches!(refused, Err(MeshError::Stranger(named)) if named == said));
		}
	}

	#[tokio::test]
	async fn a_pong_times_the_round_trip_to_the_neighbor_that_sent_it() {
		let relay = relay("rdu");
		let (feed, incoming) = mpsc::unbounded_channel();
		let hello = Message::Hello {
			version: VERSION,
			node: "tyo".into(),
			versions: Versions::new(),
			runs: None,
		};
		feed.send(Received::Text(serde_json::to_string(&hello).unwrap())).unwrap();
		let fake = Fake { incoming, sent: Arc::default(), echo: Some(feed) };
		let conversing = tokio::spawn(converse(relay.clone(), Some("tyo"), fake));
		let timed = async {
			while relay.round_trips().is_empty() {
				tokio::time::sleep(Duration::from_millis(5)).await;
			}
		};
		tokio::time::timeout(Duration::from_secs(5), timed).await.expect("the first ping, timed");
		conversing.abort();
		let round_trips = relay.round_trips();
		assert_eq!(round_trips.keys().collect::<Vec<_>>(), ["tyo"]);
		assert!((0.0..1000.0).contains(&round_trips["tyo"]));
	}

	#[test]
	fn a_pong_carries_back_when_its_ping_was_sent() {
		let origin = Instant::now();
		let sent = origin + Duration::from_millis(40);
		let payload = stamp(origin, sent);
		let answered = sent + Duration::from_micros(151_250);
		assert_eq!(round_trip(origin, &payload, answered), Some(Duration::from_micros(151_250)));
		// One stamped later than now, and one this socket never sent, time nothing.
		assert_eq!(round_trip(origin, &payload, origin), None);
		assert_eq!(round_trip(origin, b"", answered), None);
		assert_eq!(round_trip(origin, b"four", answered), None);
	}

	#[test]
	fn the_secret_admits_and_nothing_else_does() {
		let with = |value: &str| {
			let mut headers = HeaderMap::new();
			headers.insert(AUTHORIZATION, HeaderValue::from_str(value).unwrap());
			headers
		};
		assert!(admitted(&with("Bearer s3cret"), "s3cret"));
		let wrongs =
			["Bearer s3cre", "Bearer s3cret!", "Bearer S3cret", "s3cret", "Basic s3cret", "Bearer "];
		for wrong in wrongs {
			assert!(!admitted(&with(wrong), "s3cret"), "{wrong}");
		}
		assert!(!admitted(&HeaderMap::new(), "s3cret"));
	}

	#[test]
	fn the_messages_are_tagged_by_type() {
		let versions = Versions::from([("tyo".into(), 7)]);
		let hello = Message::Hello { version: 1, node: "rdu".into(), versions, runs: None };
		assert_eq!(
			serde_json::to_value(&hello).unwrap(),
			serde_json::json!({ "type": "hello", "version": 1, "node": "rdu", "versions": { "tyo": 7 } })
		);
		let node: Message = serde_json::from_str(
			r#"{ "type": "node", "node": "tyo", "state": { "version": 8, "snapshot": { "apps": [] } } }"#,
		)
		.unwrap();
		assert!(matches!(node, Message::Node { node, state } if node == "tyo" && state.version == 8));

		// A relay older than the runs says nothing of them, and is read as such.
		let older: Message =
			serde_json::from_str(r#"{ "type": "versions", "versions": { "tyo": 7 } }"#).unwrap();
		assert!(matches!(older, Message::Versions { runs: None, .. }));
		let runs: Message = serde_json::from_str(
			r#"{ "type": "runs", "node": "tyo", "above": 3, "version": 9, "rows": [{ "version": 9,
				"id": 1, "app": "geo", "action": "deploy", "source": { "kind": "panel" },
				"outcome": "running", "started_at": "2026-10-09T12:00:00Z" }] }"#,
		)
		.unwrap();
		assert!(matches!(runs, Message::Runs(Batch { node, above: 3, version: 9, rows })
			if node == "tyo" && rows[0].event.id == 1 && rows[0].version == 9));
	}
}
