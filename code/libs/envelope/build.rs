//! Writes the module `contracts` from `model/contracts.json` before the crate builds, by
//! envelope-generator, `model/graph/tools.res`. The model's, as the interface is.

use envelope_generator::{Contracts, Generate, Unread};
use std::{env, fs, path::Path};

fn main() -> Result<(), String> {
	let contracts = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../../model/contracts.json");
	println!("cargo::rerun-if-changed={}", contracts.display());
	let unread = |u: Unread| format!("model/contracts.json, at {}: {}", u.at, u.expected);
	let text = fs::read_to_string(&contracts).map_err(|e| format!("{}: {e}", contracts.display()))?;
	let rust = Contracts::read(&text).and_then(|c| c.rust()).map_err(unread)?;
	let out = env::var("OUT_DIR").map_err(|e| format!("OUT_DIR: {e}"))?;
	fs::write(Path::new(&out).join("contracts.rs"), rust).map_err(|e| format!("{out}: {e}"))
}
