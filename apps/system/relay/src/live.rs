//! A browser's socket: every node at once, then each newer snapshot as this relay takes it.
//! Nothing a browser sends is acted on. See spec/architecture/console.md, "Live, through the
//! nearest node".

use crate::cluster::Held;
use crate::mesh::HEARTBEAT;
use crate::relay::{Relay, State, Update};
use crate::socket::{Received, Socket, SocketError};
use serde::Serialize;
use std::sync::Arc;
use std::time::Duration;
use tokio::sync::broadcast::error::RecvError;
use tokio::time::Instant;

/// A browser that has answered no ping through three heartbeats is gone.
const SILENCE: Duration = Duration::from_secs(90);

/// What a browser is sent. A browser keeps, per node, the highest version it has been sent.
#[derive(Debug, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Live {
	/// First, and again whenever this socket fell too far behind to say what it missed.
	Cluster(State),
	Node {
		node: String,
		state: Held,
	},
}

pub async fn watch<S: Socket>(relay: Arc<Relay>, mut socket: S) -> Result<(), SocketError> {
	let mut updates = relay.subscribe();
	send(&mut socket, &Live::Cluster(relay.state())).await?;
	let mut heartbeat = tokio::time::interval_at(Instant::now() + HEARTBEAT, HEARTBEAT);
	let mut heard = Instant::now();
	loop {
		tokio::select! {
			received = socket.receive() => {
				heard = Instant::now();
				if received? == Received::Closed {
					return Ok(());
				}
			}
			update = updates.recv() => match update {
				Ok(Update { node, held, .. }) => {
					send(&mut socket, &Live::Node { node, state: held }).await?;
				}
				Err(RecvError::Lagged(_)) => send(&mut socket, &Live::Cluster(relay.state())).await?,
				Err(RecvError::Closed) => return Ok(()),
			},
			_ = heartbeat.tick() => {
				if heard.elapsed() >= SILENCE {
					return Ok(());
				}
				socket.ping().await?;
			}
		}
	}
}

async fn send<S: Socket>(socket: &mut S, live: &Live) -> Result<(), SocketError> {
	socket.send_text(serde_json::to_string(live).expect("a message is a tree of strings")).await
}
