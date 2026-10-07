//! See spec/architecture/databases.md, "Backups are the data, kept off the cluster".

use std::process::ExitCode;
use std::sync::Arc;
use store::api::{self, SOCKET};
use store::config::Config;
use store::store::Store;

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
			eprintln!("store: {error}");
			return ExitCode::FAILURE;
		}
	};
	if let Err(why) = &config.source {
		eprintln!("store: the mirror cannot run until the backup store is configured: {why}");
	}
	let socket = config.data.join(SOCKET);
	let listener = match listen(&socket) {
		Ok(listener) => listener,
		Err(error) => {
			eprintln!("store: answering on {}: {error}", socket.display());
			return ExitCode::FAILURE;
		}
	};
	let routes = api::routes(Arc::new(Store::new(config)));
	tokio::select! {
		served = axum::serve(listener, routes) => {
			eprintln!("store: stopped answering: {served:?}");
			ExitCode::FAILURE
		}
		() = stopped() => ExitCode::SUCCESS,
	}
}

/// The socket in the directory host gives this app and mounts into `cron`, anyone's to connect to
/// as the database's is, since `cron` runs as another user. A file left by a run that did not stop
/// cleanly would refuse the bind.
fn listen(socket: &std::path::Path) -> std::io::Result<tokio::net::UnixListener> {
	use std::os::unix::fs::PermissionsExt;
	let _ = std::fs::remove_file(socket);
	let listener = tokio::net::UnixListener::bind(socket)?;
	std::fs::set_permissions(socket, std::fs::Permissions::from_mode(0o666))?;
	Ok(listener)
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
