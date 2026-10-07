//! See spec/architecture/packages.md.

use apk::SOCKET;
use apk::door::Door;
use packages::AppState;
use std::path::PathBuf;
use std::sync::Arc;

/// musl's allocator is slow under many small allocations, and images are built for speed; see
/// infra's spec/architecture/host.md, "An image is built for speed, and for any node of its
/// architecture".
#[global_allocator]
static ALLOCATOR: mimalloc::MiMalloc = mimalloc::MiMalloc;

/// Where this service keeps its socket.
fn directory() -> PathBuf {
	std::env::var_os("APK_DATA").map_or_else(|| "/data".into(), PathBuf::from)
}

/// Where host mounts the machine's door, read-only.
fn door() -> PathBuf {
	std::env::var_os("APK_DOOR").map_or_else(|| "/door".into(), PathBuf::from)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
	let driver = Arc::new(Door::at(door()));
	let ledger = Some(ledger::Ledger::start());
	packages::serve(AppState { driver, ledger }, &directory(), SOCKET).await
}
