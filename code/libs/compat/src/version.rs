//! [`Versioned`] for [`Version`] and [`Ranged`] for [`Range`]: the frozen core, the range a reader
//! reads, and the version written among them, RFC wnqvu.

use crate::{MAX, Range, Ranged, Refused, Unchosen, Version, Versioned};

impl Versioned for Version {
	fn new(number: u64) -> Option<Self> {
		(number <= MAX).then_some(Self(number))
	}

	fn get(self) -> u64 {
		self.0
	}
}

impl Ranged for Range {
	fn new(lowest: Version, highest: Version) -> Option<Self> {
		(lowest <= highest).then_some(Self { lowest, highest })
	}

	fn lowest(&self) -> Version {
		self.lowest
	}

	fn highest(&self) -> Version {
		self.highest
	}

	fn reads(&self, version: Version) -> Result<(), Refused> {
		if version < self.lowest {
			Err(Refused::Older { version, range: *self })
		} else if version > self.highest {
			Err(Refused::Newer { version, range: *self })
		} else {
			Ok(())
		}
	}

	fn written(ranges: &[Self]) -> Result<Version, Unchosen> {
		let highest = ranges.iter().map(|r| r.highest).min().ok_or(Unchosen::Empty)?;
		let above: Vec<usize> =
			ranges.iter().enumerate().filter(|(_, r)| r.lowest > highest).map(|(at, _)| at).collect();
		if above.is_empty() { Ok(highest) } else { Err(Unchosen::Apart { highest, above }) }
	}
}
