//! A deployment's secrets as files on tmpfs bound read-only into its container at [`INSIDE`], with
//! a sealed copy that puts them back after a reboot.

use std::collections::BTreeMap;
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};

use chacha20poly1305::aead::{Aead, Generate, KeyInit};
use chacha20poly1305::{Key, XChaCha20Poly1305, XNonce};

use crate::{Fault, Refused};

/// The bytes of a nonce, before what a seal encrypts.
const NONCE: usize = 24;

/// Where a container finds its secrets, each a file by its name.
pub(super) const INSIDE: &str = "/run/secrets";

/// What no secret is named with, so none shadows what the platform gives a container.
const PLATFORM: &str = "MONOFLAKE_";

/// A secret's bytes sealed for the driver's state, and opened again.
// Where its key is held is the seal's alone, RFC vr5lw, so another is a `Seal` of its own.
pub(super) trait Seal: Send + Sync {
	/// The bytes sealed.
	fn seal(&self, plain: &[u8]) -> Result<Vec<u8>, Fault>;
	/// The bytes a seal holds, or why they are not to be had.
	fn open(&self, sealed: &[u8]) -> Result<Vec<u8>, Fault>;
}

/// The driver's seal, XChaCha20-Poly1305 under a root-only key file in its state with a random
/// nonce each, guarding against a copy of the sealed files alone, RFC vr5lw.
pub(super) struct KeyFile {
	cipher: XChaCha20Poly1305,
}

impl KeyFile {
	/// The key the state holds, made where it holds none.
	pub(super) async fn of(state: &Path) -> Result<Self, Refused> {
		let path = state.join("secrets.key");
		let key = match tokio::fs::read(&path).await {
			Ok(bytes) => Key::try_from(bytes.as_slice())
				.map_err(|_| Refused::new("fault", format!("{}: not a key", path.display())))?,
			Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
				let key = Key::generate();
				directory(state, 0o700).await?;
				file(&path, key.as_slice(), 0o600).await?;
				key
			}
			Err(e) => return Err(failed(&path, &e)),
		};
		Ok(Self { cipher: XChaCha20Poly1305::new(&key) })
	}
}

impl Seal for KeyFile {
	fn seal(&self, plain: &[u8]) -> Result<Vec<u8>, Fault> {
		let nonce = XNonce::generate();
		let sealed =
			self.cipher.encrypt(&nonce, plain).map_err(|_| Fault("a secret was not sealed".into()))?;
		Ok(nonce.iter().copied().chain(sealed).collect())
	}

	fn open(&self, sealed: &[u8]) -> Result<Vec<u8>, Fault> {
		let unsealed = || Fault("a sealed secret does not open".into());
		let (nonce, encrypted) = sealed.split_at_checked(NONCE).ok_or_else(unsealed)?;
		let nonce = XNonce::try_from(nonce).map_err(|_| unsealed())?;
		self.cipher.decrypt(&nonce, encrypted).map_err(|_| unsealed())
	}
}

/// A secret's name as a file is named, letters, digits, `_`, `-` and `.` but not first, and not the
/// platform's own.
pub(super) fn named(name: &str) -> Result<(), Refused> {
	let file = !name.is_empty()
		&& !name.starts_with('.')
		&& name.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.'));
	if !file {
		return Err(Refused::new(
			"malformed",
			format!("the secret {name:?} is not named as a file is"),
		));
	}
	if name.starts_with(PLATFORM) {
		return Err(Refused::new("malformed", format!("a secret is not named {PLATFORM}*")));
	}
	Ok(())
}

/// Where one container's secrets are, bound into it and sealed.
pub(super) struct Places {
	/// On tmpfs, root's alone above it, its own the container's user's.
	pub(super) open: PathBuf,
	/// In the driver's state, root's alone.
	pub(super) sealed: PathBuf,
}

impl Places {
	pub(super) fn of(tmpfs: &Path, state: &Path, namespace: &str, id: &str) -> Self {
		Self {
			open: tmpfs.join(namespace).join(id),
			sealed: state.join("secrets").join(namespace).join(id),
		}
	}
}

fn failed(path: &Path, e: &std::io::Error) -> Refused {
	Refused::new("fault", format!("{}: {e}", path.display()))
}

async fn directory(path: &Path, mode: u32) -> Result<(), Refused> {
	tokio::fs::DirBuilder::new()
		.recursive(true)
		.mode(mode)
		.create(path)
		.await
		.map_err(|e| failed(path, &e))
}

async fn file(path: &Path, bytes: &[u8], mode: u32) -> Result<(), Refused> {
	use tokio::io::AsyncWriteExt;
	let mut file = tokio::fs::OpenOptions::new()
		.write(true)
		.create(true)
		.truncate(true)
		.mode(mode)
		.open(path)
		.await
		.map_err(|e| failed(path, &e))?;
	file.write_all(bytes).await.map_err(|e| failed(path, &e))?;
	file.flush().await.map_err(|e| failed(path, &e))
}

/// A path given to the container's user, where the driver runs as root; a driver that does not
/// cannot give a file away, and its own user is the container's.
fn given(path: &Path, uid: u32, gid: u32) -> Result<(), Refused> {
	let owner = std::fs::metadata(path).map_err(|e| failed(path, &e))?;
	if owner.uid() != 0 || (owner.uid() == uid && owner.gid() == gid) {
		return Ok(());
	}
	std::os::unix::fs::chown(path, Some(uid), Some(gid)).map_err(|e| failed(path, &e))
}

/// The files written where the container reads them, from the bytes given.
async fn placed(
	open: &Path,
	secrets: &BTreeMap<String, Vec<u8>>,
	uid: u32,
	gid: u32,
) -> Result<(), Refused> {
	if let Some(parent) = open.parent() {
		directory(parent, 0o700).await?;
	}
	directory(open, 0o500 | 0o200).await?;
	for (name, value) in secrets {
		let path = open.join(name);
		file(&path, value, 0o400).await?;
		given(&path, uid, gid)?;
	}
	// Written whole before it is closed to writing, and the container's user may only read it.
	tokio::fs::set_permissions(open, std::os::unix::fs::PermissionsExt::from_mode(0o500))
		.await
		.map_err(|e| failed(open, &e))?;
	given(open, uid, gid)
}

/// The secrets written for a new container, its sealed copy first.
pub(super) async fn write(
	places: &Places,
	secrets: &BTreeMap<String, Vec<u8>>,
	seal: &impl Seal,
	uid: u32,
	gid: u32,
) -> Result<(), Refused> {
	directory(&places.sealed, 0o700).await?;
	for (name, value) in secrets {
		file(&places.sealed.join(name), &seal.seal(value)?, 0o600).await?;
	}
	placed(&places.open, secrets, uid, gid).await
}

/// The secrets put back from their sealed copy where tmpfs lost them, to their owner as before.
pub(super) async fn restore(
	places: &Places,
	seal: &impl Seal,
	uid: u32,
	gid: u32,
) -> Result<(), Refused> {
	if tokio::fs::try_exists(&places.open).await.unwrap_or(false) {
		return Ok(());
	}
	let mut entries = match tokio::fs::read_dir(&places.sealed).await {
		Ok(entries) => entries,
		Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(()),
		Err(e) => return Err(failed(&places.sealed, &e)),
	};
	let mut secrets = BTreeMap::new();
	while let Some(entry) = entries.next_entry().await.map_err(|e| failed(&places.sealed, &e))? {
		let sealed = tokio::fs::read(entry.path()).await.map_err(|e| failed(&entry.path(), &e))?;
		secrets.insert(entry.file_name().to_string_lossy().into_owned(), seal.open(&sealed)?);
	}
	placed(&places.open, &secrets, uid, gid).await
}

/// Both copies gone, none there being no failure.
pub(super) async fn remove(places: &Places) -> Result<(), Refused> {
	for path in [&places.open, &places.sealed] {
		if let Ok(meta) = tokio::fs::metadata(path).await {
			// The container's own directory is closed to writing; it is opened to be emptied.
			if meta.is_dir() {
				let writable = std::os::unix::fs::PermissionsExt::from_mode(0o700);
				tokio::fs::set_permissions(path, writable).await.map_err(|e| failed(path, &e))?;
			}
		}
		match tokio::fs::remove_dir_all(path).await {
			Ok(()) => {}
			Err(e) if e.kind() == std::io::ErrorKind::NotFound => {}
			Err(e) => return Err(failed(path, &e)),
		}
	}
	Ok(())
}

#[cfg(test)]
mod tests {
	use super::*;

	fn state(test: &str) -> PathBuf {
		let state =
			PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../../../../../target/tmp/seal").join(test);
		// What an earlier run left is not this run's.
		let _ = std::fs::remove_dir_all(&state);
		state
	}

	#[tokio::test]
	async fn a_seal_opens_under_its_key_alone_and_never_tampered() {
		let state = state("open");
		let seal = KeyFile::of(&state).await.unwrap();
		let sealed = seal.seal(b"hidden").unwrap();
		assert_ne!(sealed.get(NONCE..), Some(&b"hidden"[..]));
		assert_ne!(seal.seal(b"hidden").unwrap(), sealed, "each seal its own nonce");
		assert_eq!(seal.open(&sealed).unwrap(), b"hidden");
		// The key is kept, so a driver started again opens what it sealed.
		assert_eq!(KeyFile::of(&state).await.unwrap().open(&sealed).unwrap(), b"hidden");
		let mut tampered = sealed.clone();
		if let Some(last) = tampered.last_mut() {
			*last ^= 1;
		}
		assert!(seal.open(&tampered).is_err());
		assert!(seal.open(&sealed[..10]).is_err());
		assert!(KeyFile::of(&self::state("other")).await.unwrap().open(&sealed).is_err());
	}

	#[test]
	fn a_secret_is_named_as_a_file_and_never_as_the_platform() {
		for name in ["TOKEN", "api-key.pem", "a_b"] {
			assert!(named(name).is_ok(), "{name}");
		}
		for name in ["", ".hidden", "../x", "a/b", "MONOFLAKE_FOOTING", "white space"] {
			assert_eq!(named(name).map_err(|r| r.reason), Err("malformed"), "{name}");
		}
	}
}
