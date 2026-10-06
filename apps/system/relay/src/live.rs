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
use url::Url;

/// A browser that has answered no ping through three heartbeats is gone.
const SILENCE: Duration = Duration::from_secs(90);

/// Whether a socket may open from `origin`: a page on the platform's `.app` or a name under it, or
/// no page at all -- a client that is not a browser sends no `Origin`. Anything else is a page
/// elsewhere borrowing the reader's Access cookie.
pub fn admitted(origin: Option<&str>) -> bool {
	let Some(origin) = origin else {
		return true;
	};
	let (Ok(origin), Ok(app)) = (Url::parse(origin), Url::parse(monoflake::INTERNAL_APP)) else {
		return false;
	};
	let (Some(host), Some(suffix)) = (origin.host_str(), app.host_str()) else {
		return false;
	};
	let under =
		host.strip_suffix(suffix).is_some_and(|label| label.is_empty() || label.ends_with('.'));
	origin.scheme() == app.scheme() && origin.port() == app.port() && under
}

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

#[cfg(test)]
mod tests {
	use super::*;

	fn named(host: &str) -> String {
		let app = Url::parse(monoflake::INTERNAL_APP).unwrap();
		format!("{}://{host}", app.scheme())
	}

	#[test]
	fn a_page_on_the_app_or_under_it_is_admitted() {
		let suffix = Url::parse(monoflake::INTERNAL_APP).unwrap().host_str().unwrap().to_owned();
		assert!(admitted(Some(monoflake::INTERNAL_APP)));
		assert!(admitted(Some(&named(&format!("console.{suffix}")))));
		assert!(admitted(Some(&named(&format!("relay.{suffix}")))));
	}

	#[test]
	fn a_page_elsewhere_is_refused() {
		let suffix = Url::parse(monoflake::INTERNAL_APP).unwrap().host_str().unwrap().to_owned();
		for host in ["evil.test".to_owned(), format!("{suffix}.evil.test"), format!("evil{suffix}")] {
			assert!(!admitted(Some(&named(&host))), "{host}");
		}
		// The right name, by plain HTTP or on another port; and an opaque origin.
		assert!(!admitted(Some(&format!("http://{suffix}"))));
		assert!(!admitted(Some(&format!("{}:8443", monoflake::INTERNAL_APP))));
		assert!(!admitted(Some("null")));
	}

	#[test]
	fn a_client_that_is_no_browser_is_admitted() {
		assert!(admitted(None));
	}
}
