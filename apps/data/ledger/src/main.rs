//! ledger: every task any service was asked to do. See spec/architecture/ledger.md.

use ledger_service::api::{self, Shared};
use ledger_service::import;
use ledger_service::store::Store;
use std::sync::Arc;

/// musl's allocator is slow under many small allocations, and images are built for speed; see
/// infra's spec/architecture/host.md, "An image is built for speed, and for any node of its
/// architecture".
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

/// This service's port, inside its container and everywhere else. `service.toml` states it for
/// host, and the test below holds the two together.
const PORT: u16 = 12010;

/// `ledger` answers; `ledger import <ledger.db>` copies the SQLite it kept before into the
/// database once, and says what it wrote. Both bring the schema up to date first.
#[tokio::main]
async fn main() -> anyhow::Result<()> {
	let url = std::env::var("DATABASE_URL")
		.map_err(|_| anyhow::anyhow!("DATABASE_URL is not set; `mise run database grant` writes it"))?;
	let store = Store::connect(&url, None)?;
	let applied = store.migrate().await?;
	if !applied.is_empty() {
		eprintln!("ledger: applied migrations {applied:?}");
	}

	let arguments: Vec<String> = std::env::args().skip(1).collect();
	if let [verb, path] = &arguments[..]
		&& verb == "import"
	{
		let imported = import::import(&store, std::path::Path::new(path)).await?;
		println!("{}", serde_json::to_string(&imported)?);
		return Ok(());
	}
	if !arguments.is_empty() {
		anyhow::bail!("ledger takes nothing, or `import <ledger.db>`");
	}

	let listen = std::env::var("LISTEN").unwrap_or_else(|_| format!("0.0.0.0:{PORT}"));
	let shared: Shared = Arc::new(store);
	let listener = tokio::net::TcpListener::bind(&listen).await?;
	eprintln!("ledger: listening on {listen}");
	axum::serve(listener, api::routes(shared)).with_graceful_shutdown(stopped()).await?;
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
		assert!(declaration.lines().any(|line| line.trim() == format!("port = {}", super::PORT)));
	}
}
