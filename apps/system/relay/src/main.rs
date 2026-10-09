//! relay: every node's live state, on every node. See spec/architecture/relay.md.

use relay::config::Config;
use relay::host::Host;
use relay::presence::sweep;
use relay::relay::{Relay, recall, watch, write};
use relay::runs::Store;
use std::sync::Arc;

/// musl's allocator is slow under many small allocations, and images are built for speed; see
/// infra's spec/architecture/host.md, "An image is built for speed, and for any node of its
/// architecture".
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
	let config = Config::from_env()?;
	let store = Store::open(&config.data.join(relay::runs::FILE))?;
	let peers = config.peers.iter().map(|peer| peer.name.clone()).collect();
	let relay = Relay::new(config.node.clone(), config.secret.clone(), peers, store)?;

	let host = Arc::new(Host::new(monoflake::INTERNAL_HOST, config.read_token.clone()));
	tokio::spawn(watch(relay.clone(), host.clone(), relay::own::EVERY));
	tokio::spawn(recall(relay.clone(), host.clone()));
	tokio::spawn(write(relay.clone(), relay::runs::WRITE));
	tokio::spawn(sweep(relay.clone(), relay::presence::SWEEP));
	for peer in config.peers.iter().cloned() {
		tokio::spawn(relay::mesh::keep(relay.clone(), peer));
	}

	let listener = tokio::net::TcpListener::bind(&config.listen).await?;
	let named: Vec<&str> = config.peers.iter().map(|peer| peer.name.as_str()).collect();
	eprintln!("relay: {} listening on {}, holding {}", config.node, config.listen, named.join(" "));
	let routes = relay::api::routes(relay.clone());
	// Said while the mesh and the routes still run; see spec/architecture/relay.md, "A node says
	// it is leaving before it goes".
	let leaving = {
		let relay = relay.clone();
		async move {
			stopped().await;
			relay::leaving::leave(&relay, &*host).await;
		}
	};
	axum::serve(listener, routes).with_graceful_shutdown(leaving).await?;
	// What the window holds unwritten, so a deploy does not ask the neighbors for it again.
	if let Err(error) = relay.write_runs().await {
		eprintln!("relay: writing the runs: {error}");
	}
	Ok(())
}

/// `docker stop` sends SIGTERM, and a process that is PID 1 in its container ignores it unless it
/// asks; without this every deploy would wait out Docker's grace period and then be killed.
async fn stopped() {
	let interrupted = async {
		let _ = tokio::signal::ctrl_c().await;
	};
	let terminated = async {
		if let Ok(mut signal) =
			tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
		{
			signal.recv().await;
		}
	};
	tokio::select! {
		() = interrupted => {}
		() = terminated => {}
	}
}

#[cfg(test)]
mod tests {
	#[test]
	fn the_port_is_the_one_the_declaration_states() {
		let declaration = include_str!("../service.toml");
		let port = relay::config::PORT;
		assert!(declaration.lines().any(|line| line.trim() == format!("port = {port}")));
	}
}
