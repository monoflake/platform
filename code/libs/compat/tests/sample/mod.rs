//! The samples read as they stand from their paths, JSON.

use std::path::Path;

/// The sample at `path`.
pub fn read(path: impl AsRef<Path>) -> serde_json::Value {
	let path = path.as_ref();
	let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
	serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

/// The items of a JSON array.
pub fn items(value: &serde_json::Value) -> &[serde_json::Value] {
	value.as_array().unwrap_or_else(|| panic!("{value}: no array"))
}
