//! `/proc/stat`'s `cpu` and `cpuN` lines.

use super::scan::{counters, malformed, past_end};
use crate::{Parse, Processor, Times, Unread};

const EXPECTED: &str =
	"cpu and at least eight counters: user nice system idle iowait irq softirq steal";

/// The times a `cpu` line's words write: the first eight columns, any further ones read to be
/// counters and left.
fn times<'a>(words: impl Iterator<Item = &'a str>) -> Option<Times> {
	let values = counters(words)?;
	let [user, nice, system, idle, iowait, irq, softirq, steal, ..] = values.as_slice() else {
		return None;
	};
	Some(Times {
		user: *user,
		nice: *nice,
		system: *system,
		idle: *idle,
		iowait: *iowait,
		irq: *irq,
		softirq: *softirq,
		steal: *steal,
	})
}

impl Parse for Processor {
	const FILE: &'static str = "proc/stat";

	fn parse(text: &str) -> Result<Self, Unread> {
		let mut total = None;
		let mut cores: Vec<(u64, Times)> = Vec::new();
		for (number, line) in super::scan::lines(text) {
			let mut words = line.split_whitespace();
			let Some(suffix) = words.next().and_then(|name| name.strip_prefix("cpu")) else {
				continue;
			};
			if suffix.is_empty() {
				total = Some(times(words).ok_or_else(|| malformed(Self::FILE, number, EXPECTED))?);
			} else if let Some(index) = super::scan::counter(suffix) {
				let read = times(words).ok_or_else(|| malformed(Self::FILE, number, EXPECTED))?;
				cores.push((index, read));
			}
		}
		let total = total.ok_or_else(|| malformed(Self::FILE, past_end(text), "a cpu line"))?;
		cores.sort_by_key(|(index, _)| *index);
		Ok(Self { total, cores: cores.into_iter().map(|(_, read)| read).collect() })
	}
}
