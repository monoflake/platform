//! Relays on loopback ports, each reading a fake host, holding sockets to each other as they do
//! across the tailnet.

use futures_util::StreamExt;
use relay::config::Peer;
use relay::host::{App, Reader, Reading};
use relay::relay::{Relay, watch};
use std::future::{Future, IntoFuture};
use std::net::SocketAddr;
use std::pin::Pin;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use tokio_tungstenite::tungstenite::Message;

const SECRET: &str = "s3cret";
const ROUND: Duration = Duration::from_millis(20);
const PATIENCE: Duration = Duration::from_secs(10);

/// A host running one app, `geo`, at an image the test changes.
struct Fake(Mutex<String>);

impl Fake {
	fn deploy(&self, image: &str) {
		*self.0.lock().unwrap() = image.to_owned();
	}
}

impl Reader for Fake {
	fn read(&self) -> Pin<Box<dyn Future<Output = Reading> + Send + '_>> {
		let image = self.0.lock().unwrap().clone();
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
			Reading { events: Ok(vec![]), apps: Ok(vec![app]), machine: Ok(serde_json::json!({})) }
		})
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
	let relay = Relay::new(node.into(), SECRET.into());
	let host = Arc::new(Fake(Mutex::new(image.into())));
	tokio::spawn(axum::serve(listener, relay::api::routes(relay.clone())).into_future());
	tokio::spawn(watch(relay.clone(), host.clone(), ROUND));
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
	loop {
		let next = text(&mut browser).await;
		if next["type"] == "node" && next["node"] == "tyo" {
			assert_eq!(next["state"]["snapshot"]["apps"][0]["image"], "geo:8");
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
