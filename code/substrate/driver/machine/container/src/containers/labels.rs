//! What the driver keeps of a container, written on it as labels, so a restart reads it back.

use std::collections::BTreeMap;

use envelope::contracts::{DeploymentRuns, DeploymentRuntime};

/// What the container runs, as [`runs`] writes it.
pub(super) const RUNS: &str = "monoflake.runs";
/// The version, its hash in hex.
pub(super) const VERSION: &str = "monoflake.version";
const RUNTIME: &str = "monoflake.runtime";
const ADDRESS: &str = "monoflake.address";
const PORT: &str = "monoflake.port";
const USER: &str = "monoflake.user";

/// A deployment's runs as a label holds it, `app/<id>` or `component/<name>`.
pub(super) fn runs(runs: &DeploymentRuns) -> String {
	match runs {
		DeploymentRuns::App { id } => format!("app/{id}"),
		DeploymentRuns::Component { component } => format!("component/{component}"),
	}
}

/// A hash from its hex, none where it is not 64 hex digits.
pub(super) fn unhex(text: &str) -> Option<[u8; 32]> {
	let mut hash = [0u8; 32];
	if text.len() != 64 {
		return None;
	}
	for (byte, at) in hash.iter_mut().zip((0..64).step_by(2)) {
		*byte = u8::from_str_radix(text.get(at..at + 2)?, 16).ok()?;
	}
	Some(hash)
}

fn runtime_name(runtime: DeploymentRuntime) -> &'static str {
	match runtime {
		DeploymentRuntime::Workers => "workers",
		DeploymentRuntime::Workerd => "workerd",
		DeploymentRuntime::Wasmtime => "wasmtime",
		DeploymentRuntime::Runc => "runc",
		DeploymentRuntime::Crun => "crun",
		DeploymentRuntime::Youki => "youki",
	}
}

fn runtime_named(name: &str) -> Option<DeploymentRuntime> {
	match name {
		"runc" => Some(DeploymentRuntime::Runc),
		"crun" => Some(DeploymentRuntime::Crun),
		"youki" => Some(DeploymentRuntime::Youki),
		_ => None,
	}
}

/// Everything a container's labels hold.
pub(super) struct Kept {
	pub(super) runs: String,
	pub(super) version: String,
	pub(super) runtime: DeploymentRuntime,
	pub(super) address: String,
	pub(super) port: u16,
	/// Who its process runs as, `uid:gid`, whose its secrets' files are.
	pub(super) user: (u32, u32),
}

impl Kept {
	pub(super) fn write(&self) -> BTreeMap<String, String> {
		BTreeMap::from([
			(RUNS.to_owned(), self.runs.clone()),
			(VERSION.to_owned(), self.version.clone()),
			(RUNTIME.to_owned(), runtime_name(self.runtime).to_owned()),
			(ADDRESS.to_owned(), self.address.clone()),
			(PORT.to_owned(), self.port.to_string()),
			(USER.to_owned(), format!("{}:{}", self.user.0, self.user.1)),
		])
	}

	/// What the labels hold, or which is missing or spoiled.
	pub(super) fn read(labels: &BTreeMap<String, String>) -> Result<Self, String> {
		let get = |key: &str| labels.get(key).ok_or_else(|| format!("no label {key}"));
		Ok(Self {
			runs: get(RUNS)?.clone(),
			version: get(VERSION)?.clone(),
			runtime: runtime_named(get(RUNTIME)?)
				.ok_or_else(|| format!("the label {RUNTIME} names no runtime"))?,
			address: get(ADDRESS)?.clone(),
			port: get(PORT)?.parse().map_err(|_| format!("the label {PORT} is no port"))?,
			user: get(USER)?
				.split_once(':')
				.and_then(|(u, g)| Some((u.parse().ok()?, g.parse().ok()?)))
				.ok_or_else(|| format!("the label {USER} is no uid:gid"))?,
		})
	}
}
