//! The Grok CLI binaries on the volume: the one that last passed the check, and whichever is being
//! tried. See spec/architecture/grok/deployment.md, "The image carries grok2api; the CLI lives on
//! the volume".

use std::path::{Path, PathBuf};

use anyhow::{Context, Result, bail};
use futures_util::StreamExt;
use tokio::io::AsyncWriteExt;

/// Where xAI publishes the CLI: `<base>/<channel>` names a version,
/// `<base>/grok-<version>-<platform>` is the binary. The same layout `https://x.ai/cli/install.sh`
/// reads.
const BASE_URL: &str = monoflake::EXTERNAL_GROK_CLI;

/// The file naming the version that last passed the check.
const GOOD: &str = "good";

pub struct Binaries {
	dir: PathBuf,
}

impl Binaries {
	pub fn new(dir: PathBuf) -> Result<Self> {
		std::fs::create_dir_all(&dir).with_context(|| format!("cannot create {}", dir.display()))?;
		Ok(Self { dir })
	}

	pub fn path(&self, version: &str) -> PathBuf {
		self.dir.join(format!("grok-{version}"))
	}

	/// Where a binary is written before it is moved into place, so a half-written file is never
	/// at a path something runs. `with_extension` would cut the version at its last dot.
	fn partial(&self, version: &str) -> PathBuf {
		self.dir.join(format!("grok-{version}.partial"))
	}

	/// The version that last passed the check, if its binary is still here.
	pub fn good(&self) -> Option<String> {
		let version = std::fs::read_to_string(self.dir.join(GOOD)).ok()?.trim().to_owned();
		self.path(&version).is_file().then_some(version)
	}

	pub fn mark_good(&self, version: &str) -> Result<()> {
		let temporary = self.dir.join(format!("{GOOD}.tmp"));
		std::fs::write(&temporary, version)?;
		std::fs::rename(&temporary, self.dir.join(GOOD))?;
		Ok(())
	}

	/// The binary to start with: the last good one, or else the seed the image carries, copied
	/// onto the volume so a first start needs no network.
	pub async fn initial(&self, seed: &Path) -> Result<String> {
		if let Some(version) = self.good() {
			return Ok(version);
		}
		let version = version_of(seed)
			.await
			.with_context(|| format!("the seed {} does not run", seed.display()))?;
		let target = self.path(&version);
		let temporary = self.partial(&version);
		tokio::fs::copy(seed, &temporary).await?;
		tokio::fs::rename(&temporary, &target).await?;
		self.mark_good(&version)?;
		tracing::info!(version, "installed the seed CLI");
		Ok(version)
	}

	/// Downloads a version's binary unless it is already here.
	pub async fn download(&self, client: &reqwest::Client, version: &str) -> Result<PathBuf> {
		let target = self.path(version);
		if target.is_file() {
			return Ok(target);
		}
		let url = format!("{BASE_URL}/grok-{version}-{}", platform()?);
		tracing::info!(url, "downloading the CLI");
		let response = client.get(&url).send().await?.error_for_status()?;
		let temporary = self.partial(version);
		let mut file = tokio::fs::File::create(&temporary).await?;
		let mut body = response.bytes_stream();
		while let Some(chunk) = body.next().await {
			file.write_all(&chunk?).await?;
		}
		file.flush().await?;
		drop(file);
		make_executable(&temporary)?;
		tokio::fs::rename(&temporary, &target).await?;
		Ok(target)
	}

	pub fn remove(&self, version: &str) {
		let _ = std::fs::remove_file(self.path(version));
	}

	/// Removes every binary but the ones named, and any download that did not finish.
	pub fn prune(&self, keep: &[&str]) {
		let Ok(entries) = std::fs::read_dir(&self.dir) else { return };
		let keep: Vec<PathBuf> = keep.iter().map(|version| self.path(version)).collect();
		for entry in entries.flatten() {
			let path = entry.path();
			let name = entry.file_name();
			let name = name.to_string_lossy();
			if name.starts_with("grok-") && !keep.contains(&path) {
				tracing::debug!(path = %path.display(), "removing an old CLI");
				let _ = std::fs::remove_file(&path);
			}
		}
	}
}

/// The version a channel currently points at.
pub async fn channel_version(client: &reqwest::Client, channel: &str) -> Result<String> {
	let body =
		client.get(format!("{BASE_URL}/{channel}")).send().await?.error_for_status()?.text().await?;
	let version = body.lines().next().unwrap_or_default().trim().to_owned();
	if !valid_version(&version) {
		bail!("the {channel} channel pointer is not a version: {version:?}");
	}
	Ok(version)
}

/// The version a binary reports: `grok 1.0.41 (4220f3b224a6) [stable]`.
pub async fn version_of(binary: &Path) -> Result<String> {
	let output = tokio::process::Command::new(binary).arg("--version").output().await?;
	let text = String::from_utf8_lossy(&output.stdout);
	let version = text.split_whitespace().nth(1).unwrap_or_default().to_owned();
	if !output.status.success() || !valid_version(&version) {
		bail!("{} --version said {:?}", binary.display(), text.trim());
	}
	Ok(version)
}

/// `X.Y.Z` with an optional suffix, the shape the installer accepts. Checked because the version
/// becomes part of a URL and a file name.
fn valid_version(version: &str) -> bool {
	let (core, suffix) = version.split_once('-').unwrap_or((version, ""));
	let numbers: Vec<&str> = core.split('.').collect();
	numbers.len() == 3
		&& numbers.iter().all(|n| !n.is_empty() && n.bytes().all(|b| b.is_ascii_digit()))
		&& suffix.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'.' || b == b'_')
}

/// The platform name in xAI's artifact names.
fn platform() -> Result<&'static str> {
	Ok(match (std::env::consts::OS, std::env::consts::ARCH) {
		("linux", "aarch64") => "linux-aarch64",
		("linux", "x86_64") => "linux-x86_64",
		("macos", "aarch64") => "macos-aarch64",
		("macos", "x86_64") => "macos-x86_64",
		(os, arch) => bail!("no Grok CLI is published for {os}-{arch}"),
	})
}

#[cfg(unix)]
fn make_executable(path: &Path) -> Result<()> {
	use std::os::unix::fs::PermissionsExt;
	std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o755))?;
	Ok(())
}

#[cfg(not(unix))]
fn make_executable(_: &Path) -> Result<()> {
	Ok(())
}

#[cfg(test)]
mod tests {
	use super::valid_version;

	#[test]
	fn versions() {
		assert!(valid_version("1.0.41"));
		assert!(valid_version("0.1.151-alpha.2"));
		assert!(!valid_version("1.0"));
		assert!(!valid_version("1.0.41/../../x"));
		assert!(!valid_version(""));
	}
}
