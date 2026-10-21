//! The rates between two readings.

use super::scan::float;
use crate::{Between, Busy, Rates, Times, Usage};

/// What a counter grew by; one that went back counts from zero.
fn grown(earlier: u64, later: u64) -> u64 {
	if later >= earlier { later - earlier } else { later }
}

/// What a counter grew by in a second.
fn rate(earlier: u64, later: u64, seconds: f64) -> f64 {
	float(grown(earlier, later)) / seconds
}

/// The share of the ticks between two readings that were not idle.
fn share(earlier: &Times, later: &Times) -> Busy {
	let idle = grown(earlier.idle, later.idle).saturating_add(grown(earlier.iowait, later.iowait));
	let busy = [
		grown(earlier.user, later.user),
		grown(earlier.nice, later.nice),
		grown(earlier.system, later.system),
		grown(earlier.irq, later.irq),
		grown(earlier.softirq, later.softirq),
		grown(earlier.steal, later.steal),
	]
	.into_iter()
	.fold(0_u64, u64::saturating_add);
	let ticks = busy.saturating_add(idle);
	if ticks == 0 {
		return Busy(0.0);
	}
	Busy((float(busy) / float(ticks)).clamp(0.0, 1.0))
}

impl Between for Usage {
	fn since(&self, earlier: &Self) -> Option<Rates> {
		let milliseconds = self.at.checked_sub(earlier.at).filter(|elapsed| *elapsed > 0)?;
		let seconds = float(milliseconds) / 1000.0;
		let cores = self
			.processor
			.cores
			.iter()
			.zip(&earlier.processor.cores)
			.map(|(later, before)| share(before, later))
			.collect();
		let disks = self
			.disks
			.0
			.iter()
			.filter_map(|later| {
				let before = earlier.disks.0.iter().find(|d| d.device == later.device)?;
				Some((
					later.device.clone(),
					rate(before.read_bytes, later.read_bytes, seconds),
					rate(before.written_bytes, later.written_bytes, seconds),
				))
			})
			.collect();
		let interfaces = self
			.interfaces
			.0
			.iter()
			.filter_map(|later| {
				let before = earlier.interfaces.0.iter().find(|i| i.name == later.name)?;
				Some((
					later.name.clone(),
					rate(before.received_bytes, later.received_bytes, seconds),
					rate(before.sent_bytes, later.sent_bytes, seconds),
				))
			})
			.collect();
		Some(Rates {
			seconds,
			busy: (share(&earlier.processor.total, &self.processor.total), cores),
			disks,
			interfaces,
		})
	}
}
