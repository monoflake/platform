//! `/proc/meminfo`, whose sizes are kilobytes of 1024 bytes.

use super::scan::{counter, lines, malformed, past_end};
use crate::{Memory, Parse, Unread};

const KEYS: [&str; 7] =
	["MemTotal", "MemAvailable", "MemFree", "Buffers", "Cached", "SwapTotal", "SwapFree"];

/// A value of the form `1116304 kB`, in bytes.
fn bytes(value: &str) -> Option<u64> {
	let mut words = value.split_whitespace();
	let size = counter(words.next()?)?;
	if words.next()? != "kB" || words.next().is_some() {
		return None;
	}
	size.checked_mul(1024)
}

impl Parse for Memory {
	const FILE: &'static str = "proc/meminfo";

	fn parse(text: &str) -> Result<Self, Unread> {
		let mut found: Vec<(&str, u64)> = Vec::new();
		for (number, line) in lines(text) {
			let Some((key, value)) = line.split_once(':') else {
				return Err(malformed(Self::FILE, number, "a name, a colon and a value"));
			};
			if let Some(wanted) = KEYS.iter().find(|wanted| **wanted == key) {
				let size = bytes(value).ok_or_else(|| malformed(Self::FILE, number, "a size in kB"))?;
				found.push((wanted, size));
			}
		}
		let get = |key: &str| {
			found
				.iter()
				.find(|(name, _)| *name == key)
				.map(|(_, size)| *size)
				.ok_or_else(|| malformed(Self::FILE, past_end(text), key))
		};
		Ok(Self {
			total: get("MemTotal")?,
			available: get("MemAvailable")?,
			free: get("MemFree")?,
			buffers: get("Buffers")?,
			cached: get("Cached")?,
			swap_total: get("SwapTotal")?,
			swap_free: get("SwapFree")?,
		})
	}
}
