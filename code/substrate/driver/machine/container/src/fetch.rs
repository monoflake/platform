//! An artifact fetched to a file, held to its bound and hashed as it is written, RFC ge55b.

use std::os::unix::fs::MetadataExt;
use std::path::{Component, Path};

use sha2::{Digest, Sha256};
use tokio::io::{AsyncReadExt, AsyncWriteExt};

use crate::{Fetch, Https, Unfetched};

/// How much is read at once from a file.
const CHUNK: usize = 64 * 1024;

/// What a `file:` address refused is answered, naming no path and no error of the system.
const NOT_SERVED: &str = "a file: address names no artifact this machine serves";
/// What a copy that failed is answered, as plainly.
const UNREAD: &str = "the artifact could not be read whole";

fn unfetchable(why: impl Into<String>) -> Unfetched {
	Unfetched::Unfetchable(why.into())
}

impl Fetch for Https {
	async fn fetch(&self, address: &str, into: &Path, most: u64) -> Result<[u8; 32], Unfetched> {
		if let Some(rest) = address.strip_prefix("file:") {
			let local = self.local.as_deref().ok_or_else(|| unfetchable(NOT_SERVED))?;
			let path = Path::new(rest.strip_prefix("//").unwrap_or(rest));
			let file = served(local, path).await.ok_or_else(|| unfetchable(NOT_SERVED))?;
			return copied(file, into, most).await;
		}
		if address.starts_with("https://") {
			// open: fetching over HTTPS waits on a client whose graph the license policy takes;
			// reqwest 0.13 brings webpki-root-certs, CDLA-Permissive-2.0, through its verifier.
			return Err(unfetchable("fetching over HTTPS is not built yet"));
		}
		Err(unfetchable("an artifact's address is https: or file:"))
	}
}

/// The file a path names, opened, where it is a regular file, no link, and lies within the
/// directory once both are canonical; none otherwise.
async fn served(local: &Path, path: &Path) -> Option<tokio::fs::File> {
	if !path.is_absolute() || path.components().any(|c| matches!(c, Component::ParentDir)) {
		return None;
	}
	let root = tokio::fs::canonicalize(local).await.ok()?;
	let seen = tokio::fs::symlink_metadata(path).await.ok()?;
	if !seen.file_type().is_file() {
		return None;
	}
	if !tokio::fs::canonicalize(path).await.ok()?.starts_with(&root) {
		return None;
	}
	let file = tokio::fs::File::open(path).await.ok()?;
	// What was opened is what was looked at, not a link put in its place between the two.
	let opened = file.metadata().await.ok()?;
	(opened.dev() == seen.dev() && opened.ino() == seen.ino()).then_some(file)
}

/// Bytes written to a file as they come, hashed, and held to the bound.
struct Sink {
	file: tokio::fs::File,
	hasher: Sha256,
	total: u64,
	most: u64,
}

impl Sink {
	async fn new(into: &Path, most: u64) -> Result<Self, Unfetched> {
		if let Some(parent) = into.parent() {
			tokio::fs::create_dir_all(parent).await.map_err(|_| unfetchable(UNREAD))?;
		}
		let file = tokio::fs::File::create(into).await.map_err(|_| unfetchable(UNREAD))?;
		Ok(Self { file, hasher: Sha256::new(), total: 0, most })
	}

	async fn take(&mut self, chunk: &[u8]) -> Result<(), Unfetched> {
		self.total = self.total.saturating_add(u64::try_from(chunk.len()).unwrap_or(u64::MAX));
		// What is sent may be more than it said, so the bound is held on what came.
		if self.total > self.most {
			return Err(Unfetched::TooLarge);
		}
		self.hasher.update(chunk);
		self.file.write_all(chunk).await.map_err(|_| unfetchable(UNREAD))
	}

	async fn done(mut self) -> Result<[u8; 32], Unfetched> {
		self.file.flush().await.map_err(|_| unfetchable(UNREAD))?;
		Ok(self.hasher.finalize().into())
	}
}

async fn copied(
	mut source: tokio::fs::File,
	into: &Path,
	most: u64,
) -> Result<[u8; 32], Unfetched> {
	let size = source.metadata().await.map_err(|_| unfetchable(UNREAD))?.len();
	if size > most {
		return Err(Unfetched::TooLarge);
	}
	let mut sink = Sink::new(into, most).await?;
	let mut buffer = vec![0u8; CHUNK];
	loop {
		let read = source.read(&mut buffer).await.map_err(|_| unfetchable(UNREAD))?;
		match buffer.get(..read).filter(|c| !c.is_empty()) {
			Some(chunk) => sink.take(chunk).await?,
			None => return sink.done().await,
		}
	}
}
