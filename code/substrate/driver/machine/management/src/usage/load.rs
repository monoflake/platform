//! `/proc/loadavg`.

use super::scan::malformed;
use crate::{Load, Parse, Unread};

const EXPECTED: &str = "three load averages, numbers of tasks";

/// An average, a finite number that is not negative.
fn average(word: &str) -> Option<f64> {
	word.parse::<f64>().ok().filter(|value| value.is_finite() && *value >= 0.0)
}

impl Parse for Load {
	const FILE: &'static str = "proc/loadavg";

	fn parse(text: &str) -> Result<Self, Unread> {
		let words: Vec<&str> = text.lines().next().unwrap_or("").split_whitespace().collect();
		let [one, five, fifteen, ..] = words.as_slice() else {
			return Err(malformed(Self::FILE, 1, EXPECTED));
		};
		match (average(one), average(five), average(fifteen)) {
			(Some(one), Some(five), Some(fifteen)) => Ok(Self { one, five, fifteen }),
			_ => Err(malformed(Self::FILE, 1, EXPECTED)),
		}
	}
}
