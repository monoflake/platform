//! Relays on loopback ports, each reading a fake host, holding sockets to each other as they do
//! across the tailnet.

use bytes::Bytes;
use futures_util::StreamExt;
use http_body_util::{BodyExt, Empty};
use hyper::body::Incoming;
use hyper_util::client::legacy::Client;
use hyper_util::client::legacy::connect::HttpConnector;
use hyper_util::rt::TokioExecutor;
use relay::config::Peer;
use relay::host::{App, Event, PAGE, ReadError, Reader, Reading, Source};
use relay::relay::{Relay, recall, watch};
use relay::runs::Store;
use std::future::{Future, IntoFuture};
use std::net::SocketAddr;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

const SECRET: &str = "s3cret";
const ROUND: Duration = Duration::from_millis(20);
const PATIENCE: Duration = Duration::from_secs(10);

/// A host running one app, `geo`, at an image the test changes, and the events the test writes.
struct Fake {
	image: Mutex<String>,
	events: Mutex<Vec<Event>>,
}

impl Fake {
	fn deploy(&self, image: &str) {
		*self.image.lock().unwrap() = image.to_owned();
	}

	/// An event of `id` written, or rewritten with its outcome moved on.
	fn record(&self, id: i64, outcome: &str) {
		let event = Event {
			id,
			app: "geo".into(),
			action: "deploy".into(),
			source: Source { kind: "panel".into(), run: None, commit: None },
			image: None,
			outcome: outcome.into(),
			stage: None,
			detail: None,
			started_at: jiff::Timestamp::now().to_string(),
			finished_at: None,
		};
		let mut events = self.events.lock().unwrap();
		events.retain(|written| written.id != id);
		events.push(event);
		events.sort_by_key(|event| -event.id);
	}

	fn before(&self, before: Option<i64>) -> Vec<Event> {
		let events = self.events.lock().unwrap();
		let older = events.iter().filter(|event| before.is_none_or(|before| event.id < before));
		older.take(PAGE).cloned().collect()
	}
}

impl Reader for Fake {
	fn read(&self) -> Pin<Box<dyn Future<Output = Reading> + Send + '_>> {
		let image = self.image.lock().unwrap().clone();
		let events = self.before(None);
		Box::pin(async move {
			let app = App {
				name: "geo".into(),
				image,
				deployed_at: "2026-10-06T12:00:00Z".into(),
				running: true,
				held: false,
				rollout: "beside".into(),
				label: None,
			};
			Reading { events: Ok(events), apps: Ok(vec![app]), machine: Ok(serde_json::json!({})) }
		})
	}

	fn page(
		&self,
		before: Option<i64>,
	) -> Pin<Box<dyn Future<Output = Result<Vec<Event>, ReadError>> + Send + '_>> {
		let events = self.before(before);
		Box::pin(async move { Ok(events) })
	}
}

struct Started {
	relay: Arc<Relay>,
	host: Arc<Fake>,
	address: SocketAddr,
}

async fn start(node: &str, image: &str) -> Started {
	let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
	let address = listener.local_addr().unwrap();
	let relay = Relay::new(node.into(), SECRET.into(), Store::memory().unwrap()).unwrap();
	let host = Arc::new(Fake { image: Mutex::new(image.into()), events: Mutex::default() });
	tokio::spawn(axum::serve(listener, relay::api::routes(relay.clone())).into_future());
	tokio::spawn(watch(relay.clone(), host.clone(), ROUND));
	tokio::spawn(recall(relay.clone(), host.clone()));
	Started { relay, host, address }
}

fn hold(from: &Started, to: &Started) {
	let peer = Peer { name: to.relay.node().into(), address: to.address.to_string() };
	tokio::spawn(relay::mesh::keep(from.relay.clone(), peer));
}

/// The image `relay` holds for `node`'s one app.
fn image(relay: &Relay, node: &str) -> Option<String> {
	let state = relay.state();
	let snapshot = &state.nodes.get(node)?.snapshot;
	snapshot["apps"][0]["image"].as_str().map(str::to_owned)
}

async fn until(what: &str, mut done: impl FnMut() -> bool) {
	let waited = async {
		while !done() {
			tokio::time::sleep(ROUND).await;
		}
	};
	tokio::time::timeout(PATIENCE, waited).await.unwrap_or_else(|_| panic!("never: {what}"));
}

#[tokio::test]
async fn two_relays_converge_after_one_changes() {
	let rdu = start("rdu", "geo:1").await;
	let tyo = start("tyo", "geo:7").await;
	hold(&rdu, &tyo);
	hold(&tyo, &rdu);
	until("each holds the other", || {
		image(&rdu.relay, "tyo").as_deref() == Some("geo:7")
			&& image(&tyo.relay, "rdu").as_deref() == Some("geo:1")
	})
	.await;

	let (mut browser, _) =
		tokio_tungstenite::connect_async(format!("ws://{}/live", rdu.address)).await.unwrap();
	let first = text(&mut browser).await;
	assert_eq!((&first["type"], &first["node"]), (&"cluster".into(), &"rdu".into()));
	assert_eq!(first["version"], 1);
	assert_eq!(first["nodes"]["tyo"]["snapshot"]["apps"][0]["image"], "geo:7");
	let before = first["nodes"]["tyo"]["version"].as_u64().unwrap();

	tyo.host.deploy("geo:8");
	until("rdu hears tyo's change", || image(&rdu.relay, "tyo").as_deref() == Some("geo:8")).await;
	// tyo's round trips change its snapshot too, so one sent before the deploy may come first.
	loop {
		let next = text(&mut browser).await;
		let image = &next["state"]["snapshot"]["apps"][0]["image"];
		if next["type"] == "node" && next["node"] == "tyo" && image == "geo:8" {
			assert!(next["state"]["version"].as_u64().unwrap() > before);
			break;
		}
	}
	// Neither holds anything of the other's as its own.
	assert_eq!(image(&tyo.relay, "tyo").as_deref(), Some("geo:8"));
	assert_eq!(image(&rdu.relay, "rdu").as_deref(), Some("geo:1"));
}

#[tokio::test]
async fn a_node_reaches_a_third_through_a_neighbor() {
	// rdu and buf know tyo alone, and tyo dials nobody: it only accepts.
	let rdu = start("rdu", "geo:1").await;
	let tyo = start("tyo", "geo:2").await;
	let buf = start("buf", "geo:3").await;
	hold(&rdu, &tyo);
	hold(&buf, &tyo);
	until("rdu hears buf", || image(&rdu.relay, "buf").as_deref() == Some("geo:3")).await;
	buf.host.deploy("geo:4");
	until("rdu hears buf's change", || image(&rdu.relay, "buf").as_deref() == Some("geo:4")).await;
	until("buf hears rdu", || image(&buf.relay, "rdu").as_deref() == Some("geo:1")).await;
}

#[tokio::test]
async fn each_relay_times_the_other_and_its_snapshot_carries_it_to_the_other() {
	let rdu = start("rdu", "geo:1").await;
	let tyo = start("tyo", "geo:2").await;
	hold(&rdu, &tyo);
	// Held by tyo, as rdu's snapshot travels: rdu's own figure, never tyo's of rdu.
	let carried = |relay: &Relay, node: &str, peer: &str| {
		let state = relay.state();
		state.nodes.get(node)?.snapshot["round_trip"][peer].as_f64()
	};
	until("tyo holds rdu's round trip to it", || carried(&tyo.relay, "rdu", "tyo").is_some()).await;
	until("rdu holds tyo's round trip to it", || carried(&rdu.relay, "tyo", "rdu").is_some()).await;
	let round_trip = carried(&tyo.relay, "rdu", "tyo").unwrap();
	assert!((0.0..1.0).contains(&round_trip), "{round_trip}");
	assert_eq!(rdu.relay.state().nodes["rdu"].snapshot["round_trip"].as_object().unwrap().len(), 1);
}

/// The outcome the relay at `address` holds of `node`'s run `id`, as `/runs` answers it.
async fn outcome(address: SocketAddr, node: &str, id: i64) -> Option<String> {
	let client: Client<HttpConnector, Empty<Bytes>> =
		Client::builder(TokioExecutor::new()).build(HttpConnector::new());
	let answer: hyper::Response<Incoming> =
		client.get(format!("http://{address}/runs").parse().ok()?).await.ok()?;
	let body = answer.into_body().collect().await.ok()?.to_bytes();
	let runs: serde_json::Value = relay::host::opened(&body).ok()?;
	let run = runs["runs"].as_array()?.iter().find(|run| run["node"] == node && run["id"] == id)?;
	run["outcome"].as_str().map(str::to_owned)
}

#[tokio::test]
async fn a_run_reaches_the_other_relay_and_so_does_its_change() {
	let rdu = start("rdu", "geo:1").await;
	let tyo = start("tyo", "geo:2").await;
	// Written before either meets the other: the reading back carries it, then the window.
	tyo.host.record(7, "running");
	hold(&rdu, &tyo);
	hold(&tyo, &rdu);
	let held = || async { outcome(rdu.address, "tyo", 7).await };
	let waited = async {
		while held().await.as_deref() != Some("running") {
			tokio::time::sleep(ROUND).await;
		}
	};
	tokio::time::timeout(PATIENCE, waited).await.expect("rdu hears tyo's run");

	tyo.host.record(7, "succeeded");
	tyo.host.record(8, "running");
	let waited = async {
		while held().await.as_deref() != Some("succeeded")
			|| outcome(rdu.address, "tyo", 8).await.is_none()
		{
			tokio::time::sleep(ROUND).await;
		}
	};
	tokio::time::timeout(PATIENCE, waited).await.expect("rdu hears tyo's run change");
	assert_eq!(outcome(tyo.address, "tyo", 8).await.as_deref(), Some("running"));
}

#[tokio::test]
async fn a_relay_without_the_secret_is_refused() {
	let rdu = start("rdu", "geo:1").await;
	let stranger = Peer { name: "rdu".into(), address: rdu.address.to_string() };
	assert!(relay::mesh::dial(&stranger, "wrong").await.is_err());
	assert!(relay::mesh::dial(&stranger, SECRET).await.is_ok());
}

async fn text<S>(socket: &mut S) -> serde_json::Value
where
	S: futures_util::Stream<Item = Result<Message, tokio_tungstenite::tungstenite::Error>> + Unpin,
{
	loop {
		let next = tokio::time::timeout(PATIENCE, socket.next()).await.expect("a message in time");
		if let Message::Text(text) = next.unwrap().unwrap() {
			return serde_json::from_str(text.as_str()).unwrap();
		}
	}
}
