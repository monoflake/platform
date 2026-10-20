//! Reading the samples as they stand, from their paths: JSON, its hex in either case.

use std::path::Path;

/// The sample at `path`.
pub fn read(path: impl AsRef<Path>) -> serde_json::Value {
	let path = path.as_ref();
	let text = std::fs::read_to_string(path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
	serde_json::from_str(&text).unwrap_or_else(|e| panic!("{}: {e}", path.display()))
}

/// The bytes a hex string spells.
pub fn hex(text: &str) -> Vec<u8> {
	assert!(text.len().is_multiple_of(2), "{text}: an odd number of digits");
	(0..text.len()).step_by(2).map(|i| u8::from_str_radix(&text[i..i + 2], 16).unwrap()).collect()
}

/// A field of `value` that holds hex, read as its bytes.
pub fn hex_at(value: &serde_json::Value) -> Vec<u8> {
	hex(value.as_str().unwrap_or_else(|| panic!("{value}: no hex")))
}
