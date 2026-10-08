//! The keeper: Patroni as its child and Postgres as Patroni's, Patroni's configuration written each
//! start, and the container ended -- Postgres stopped first -- when Patroni ends unasked or stops
//! answering. See spec/architecture/databases.md, "The container is Postgres and a keeper of it".

use database::api::{self, SOCKET};
use database::config::Config;
use database::keeper::Keeper;
use database::patroni::{PATIENCE, Verdict, Watchdog};
use database::postgres::{self, Layout};
use database::render;
use std::process::ExitCode;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::process::Child;

/// musl's allocator is slow under many small allocations, and images are built for speed; see
/// infra's spec/architecture/host.md, "An image is built for speed, and for any node of its
/// architecture".
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

/// How often Patroni's liveness is asked.
const WATCH: Duration = Duration::from_secs(5);
/// How long Patroni may go unanswering before Postgres is stopped. A frozen leader last renewed its
/// lease at most `LOOP_WAIT` before it froze, so another may take it `TTL - LOOP_WAIT` after the
/// freeze; the keeper notices within this, one `WATCH` and one `PATIENCE` later, and has two
/// seconds left to stop Postgres before then.
const FENCE_AFTER: Duration = Duration::from_secs(render::TTL - render::LOOP_WAIT)
	.saturating_sub(WATCH)
	.saturating_sub(PATIENCE)
	.saturating_sub(Duration::from_secs(2));
/// How long Patroni has to stop Postgres and give up the lease when the container is stopped. Held,
/// with the keeper's own immediate stop after it, under the 20 s host gives a container before it
/// kills it: infra's libs/deploy/src/engine/mod.rs, `StopContainerOptionsBuilder::new().t(20)`.
const STOPPING: Duration = Duration::from_secs(12);

#[tokio::main]
async fn main() -> ExitCode {
	let arguments: Vec<String> = std::env::args().skip(1).collect();
	if arguments.first().map(String::as_str) == Some("fetch-backup") {
		return fetch_backup(&arguments[1..]).await;
	}
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

	let started = match keeper.prepare().await {
		Ok(()) => keeper.spawn(),
		Err(error) => Err(error),
	};
	let mut patroni = match started {
		Ok(child) => child,
		Err(error) => {
			eprintln!("database: {error}");
			return ExitCode::FAILURE;
		}
	};
	tokio::spawn(tend(keeper.clone()));

	let mut stop = std::pin::pin!(stopped());
	let mut watchdog = Watchdog::new(FENCE_AFTER);
	let mut tick = tokio::time::interval(WATCH);
	loop {
		tokio::select! {
			() = &mut stop => {
				shut_down(&keeper, &mut patroni).await;
				return ExitCode::SUCCESS;
			}
			exited = patroni.wait() => {
				eprintln!("database: Patroni exited unasked ({exited:?}); stopping Postgres now");
				stop_postgres(&keeper).await;
				return ExitCode::FAILURE;
			}
			_ = tick.tick() => {
				let alive = keeper.rest.alive().await;
				if let Verdict::Fence(silent) = watchdog.observe(alive, Instant::now()) {
					eprintln!(
						"database: Patroni has not answered alive for {}s, and its lease may soon \
						 be another's; stopping Postgres and Patroni now",
						silent.as_secs()
					);
					stop_postgres(&keeper).await;
					let _ = patroni.kill().await;
					return ExitCode::FAILURE;
				}
			}
		}
	}
}

/// Patroni's `wal_g` replica method, called by Patroni as `database fetch-backup --datadir=...` and
/// the rest of its arguments, which it does not need.
async fn fetch_backup(arguments: &[String]) -> ExitCode {
	let Some(data) = arguments.iter().find_map(|argument| argument.strip_prefix("--datadir=")) else {
		eprintln!("database: fetch-backup needs --datadir=");
		return ExitCode::FAILURE;
	};
	match postgres::fetch_backup(std::path::Path::new(data)).await {
		Ok(()) => ExitCode::SUCCESS,
		Err(error) => {
			eprintln!("database: no base backup could be fetched: {error}");
			ExitCode::FAILURE
		}
	}
}

/// Stopped in order: Patroni is asked to stop, which stops Postgres and gives up the lease if it
/// holds it, so another member takes over at once; Postgres is stopped by the keeper only if
/// Patroni does not finish in time.
async fn shut_down(keeper: &Keeper, patroni: &mut Child) {
	if let Some(pid) = patroni.id().and_then(|pid| i32::try_from(pid).ok()) {
		// SAFETY: a signal to the child this process spawned and still waits on, so `pid` is it.
		unsafe { libc::kill(pid, libc::SIGTERM) };
	}
	if tokio::time::timeout(STOPPING, patroni.wait()).await.is_err() {
		eprintln!("database: Patroni did not stop in {}s; stopping Postgres now", STOPPING.as_secs());
		stop_postgres(keeper).await;
		let _ = patroni.kill().await;
	}
}

async fn stop_postgres(keeper: &Keeper) {
	if let Err(error) = postgres::stop_now(&keeper.layout).await {
		eprintln!("database: stopping Postgres: {error}");
	}
}

/// The leader's upkeep, each minute.
async fn tend(keeper: Arc<Keeper>) {
	loop {
		tokio::time::sleep(Duration::from_secs(60)).await;
		keeper.tend().await;
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

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn a_stop_finishes_inside_hosts_grace_however_patroni_takes_it() {
		// host's grace before it kills a container; see `STOPPING`.
		const HOST_GRACE: Duration = Duration::from_secs(20);
		let worst = STOPPING + postgres::STOP_NOW + Duration::from_secs(2);
		assert!(worst < HOST_GRACE, "{worst:?}");
	}

	#[test]
	fn a_frozen_leader_is_stopped_before_its_lease_can_pass() {
		assert_eq!(FENCE_AFTER, Duration::from_secs(15));
		let noticed = FENCE_AFTER + WATCH + PATIENCE;
		assert!(noticed < Duration::from_secs(render::TTL - render::LOOP_WAIT));
	}
}
