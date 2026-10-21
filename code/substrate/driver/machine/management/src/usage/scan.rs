//! What every reader shares: a line counted from 1, a counter that is only digits, an error made
//! for a file under the root.

use crate::Unread;
use std::fs;
use std::path::{Path, PathBuf};

/// The lines of `text`, each with its number from 1.
pub(super) fn lines(text: &str) -> impl Iterator<Item = (usize, &str)> {
	text.lines().enumerate().map(|(index, line)| (index.saturating_add(1), line))
}

/// The number of the line after the last, where something the text should hold is missing.
pub(super) fn past_end(text: &str) -> usize {
	text.lines().count().saturating_add(1)
}

/// A line of `file` that is not as written.
pub(super) fn malformed(file: &str, line: usize, expected: &str) -> Unread {
	Unread::Malformed { file: PathBuf::from(file), line, expected: expected.to_owned() }
}

/// A counter: digits and nothing else, so no sign, no blank, no word.
pub(super) fn counter(word: &str) -> Option<u64> {
	if word.is_empty() || !word.bytes().all(|byte| byte.is_ascii_digit()) {
		return None;
	}
	word.parse().ok()
}

/// Every word a counter, or none of them.
pub(super) fn counters<'a>(words: impl Iterator<Item = &'a str>) -> Option<Vec<u64>> {
	words.map(counter).collect()
}

/// A count as a float, exact to the float's own precision: the two halves are exact and one
/// addition rounds, where `as` is denied.
pub(super) fn float(count: u64) -> f64 {
	let high = u32::try_from(count >> 32).unwrap_or(u32::MAX);
	let low = u32::try_from(count & u64::from(u32::MAX)).unwrap_or(u32::MAX);
	f64::from(high) * 4_294_967_296.0 + f64::from(low)
}

/// What `relative`, a path under `root`, holds.
pub(super) fn slurp(root: &Path, relative: &Path) -> Result<String, Unread> {
	fs::read_to_string(root.join(relative))
		.map_err(|error| Unread::Missing { file: relative.to_path_buf(), error: error.to_string() })
}
