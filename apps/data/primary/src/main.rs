//! See spec/todo/todo.md, "The database".

use primary::check::PIGSTY;
use primary::config::Config;
use primary::proxy::Proxy;
use primary::state::State;
use primary::{api, watch};
use std::process::ExitCode;
use std::sync::Arc;

/// musl's allocator is slow under many small allocations, and images are built for speed; see
/// infra's spec/architecture/host.md, "An image is built for speed, and for any node of its
/// architecture".
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

#[tokio::main]
async fn main() -> ExitCode {
	let config = match Config::read(|key| std::env::var(key).ok()) {
		Ok(config) => config,
		Err(error) => {
			eprintln!("primary: {error}");
			return ExitCode::FAILURE;
		}
	};
	let state = Arc::new(State::new(&config.members));
	let client = watch::asker();
	for member in &config.members {
		tokio::spawn(watch::check(member.clone(), state.clone(), PIGSTY, client.clone()));
	}
	let (listener, health) = match tokio::try_join!(
		tokio::net::TcpListener::bind(config.listen),
		tokio::net::TcpListener::bind(config.health)
	) {
		Ok(both) => both,
		Err(error) => {
			eprintln!("primary: listening: {error}");
			return ExitCode::FAILURE;
		}
	};
	eprintln!("primary: passing {} on to the member Patroni names primary", config.listen);
	tokio::spawn(Proxy::new(state.clone(), &config.members, PIGSTY).serve(listener));
	tokio::select! {
		served = axum::serve(health, api::routes(state)) => {
			eprintln!("primary: stopped answering: {served:?}");
			ExitCode::FAILURE
		}
		() = stopped() => ExitCode::SUCCESS,
	}
}

/// SIGTERM from `docker stop`, or SIGINT.
async fn stopped() {
	use tokio::signal::unix::{SignalKind, signal};
	let (Ok(mut term), Ok(mut int)) =
		(signal(SignalKind::terminate()), signal(SignalKind::interrupt()))
	else {
		return std::future::pending().await;
	};
	tokio::select! {
		_ = term.recv() => {}
		_ = int.recv() => {}
	}
}
