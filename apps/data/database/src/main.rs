//! The keeper: Postgres as its child, brought up as this node's configuration says, stopped fast
//! when the container is, and the container ended when Postgres ends unasked. See
//! spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use database::api::{self, SOCKET};
use database::config::Config;
use database::keeper::{Keeper, Stopped};
use database::postgres::{self, Layout};
use std::process::ExitCode;
use std::sync::Arc;
use std::time::Duration;

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
			eprintln!("database: {error}");
			return ExitCode::FAILURE;
		}
	};
	let keeper = Arc::new(Keeper::new(config.clone(), Layout::new(config.data.clone())));
	let socket = config.data.parent().unwrap_or(&config.data).join(SOCKET);
	let listener = match listen(&socket) {
		Ok(listener) => listener,
		Err(error) => {
			eprintln!("database: answering on {}: {error}", socket.display());
			return ExitCode::FAILURE;
		}
	};
	let routes = api::routes(keeper.clone());
	tokio::spawn(async move { axum::serve(listener, routes).await });

	let mut stop = std::pin::pin!(stopped());
	let up = tokio::select! {
		() = &mut stop => {
			// Postgres may already be up and not yet answering; it is stopped all the same.
			let _ = postgres::stop(&keeper.layout).await;
			tokio::time::sleep(Duration::from_secs(5)).await;
			return ExitCode::SUCCESS;
		}
		up = keeper.bring_up() => up,
	};
	let mut child = match up {
		Ok(child) => child,
		Err(Stopped::Refused(reason)) => {
			keeper.refuse(reason);
			stop.await;
			return ExitCode::SUCCESS;
		}
		Err(error) => {
			eprintln!("database: {error}");
			return ExitCode::FAILURE;
		}
	};
	tokio::select! {
		() = &mut stop => {
			if let Err(error) = postgres::stop(&keeper.layout).await {
				eprintln!("database: stopping Postgres: {error}");
			}
			let _ = child.wait().await;
			ExitCode::SUCCESS
		}
		exited = child.wait() => {
			eprintln!("database: Postgres exited unasked: {exited:?}");
			ExitCode::FAILURE
		}
	}
}

/// The socket beside the cluster, in the directory host gives this app and mounts into `cron`. A
/// file left by a run that did not stop cleanly would refuse the bind, and `cron` runs as another
/// user, so the socket is anyone's while the cluster stays the database user's alone. See
/// spec/architecture/databases.md, "The container is Postgres and a keeper of it".
fn listen(socket: &std::path::Path) -> std::io::Result<tokio::net::UnixListener> {
	use std::os::unix::fs::PermissionsExt;
	let _ = std::fs::remove_file(socket);
	let listener = tokio::net::UnixListener::bind(socket)?;
	std::fs::set_permissions(socket, std::fs::Permissions::from_mode(0o666))?;
	Ok(listener)
}

/// SIGTERM from `docker stop`, or SIGINT, the stop signal the Postgres image it is built on names.
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
