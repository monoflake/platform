//! The readings of `tests/buf1/` and `tests/buf2/`, two roots as the machine laid them out.

#![allow(dead_code)]

use std::fs;
use std::path::PathBuf;

/// The root of the reading named `first` (`buf1`) or `second` (`buf2`).
pub fn root(reading: &str) -> PathBuf {
	let directory = if reading == "first" { "buf1" } else { "buf2" };
	PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests").join(directory)
}

/// A file of that reading, under its root.
pub fn text(reading: &str, file: &str) -> String {
	fs::read_to_string(root(reading).join(file)).expect("a fixture file")
}

/// The milliseconds since the epoch at which that reading was taken.
pub fn at(reading: &str) -> u64 {
	text(reading, "at").trim().parse().expect("a number")
}

/// `text` with its `line`th line, from 1, replaced.
pub fn with_line(text: &str, line: usize, replacement: &str) -> String {
	text
		.lines()
		.enumerate()
		.map(|(index, old)| if index + 1 == line { replacement } else { old })
		.collect::<Vec<_>>()
		.join("\n")
}

/// Whether two floats are the same to a part in a billion.
pub fn near(left: f64, right: f64) -> bool {
	(left - right).abs() <= 1e-9 * left.abs().max(right.abs()).max(1.0)
}
