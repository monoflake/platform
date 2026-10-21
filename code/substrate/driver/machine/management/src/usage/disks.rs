//! `/proc/diskstats`: one line for each block device, a partition and a loop device among them.

use super::scan::{counter, lines, malformed};
use crate::{Disk, Disks, Parse, Unread};

const EXPECTED: &str = "major, minor, a name and ten counters";

/// A sector of the kernel's accounting, always 512 bytes, whatever the device's own.
const SECTOR: u64 = 512;

/// Names that are no disk: a loop device, a ram disk, an optical drive, a floppy.
const NOT_DISKS: [&str; 5] = ["loop", "ram", "zram", "sr", "fd"];

/// Whether `name` is a whole disk. The line holds no more than the name, so a partition is told by
/// how its disk's kind numbers it: `vda1` and `sda2` append a digit to a name made of letters,
/// `nvme0n1p1` and `mmcblk0p1` append `p` and a digit to a name that ends in one.
fn whole(name: &str) -> bool {
	if NOT_DISKS.iter().any(|prefix| name.starts_with(prefix)) {
		return false;
	}
	let ends_in_digit = name.bytes().last().is_some_and(|byte| byte.is_ascii_digit());
	if name.starts_with("nvme") || name.starts_with("mmcblk") {
		let stem = name.trim_end_matches(|c: char| c.is_ascii_digit());
		let numbered = stem.len() < name.len();
		return !(numbered
			&& stem
				.strip_suffix('p')
				.is_some_and(|before| before.ends_with(|c: char| c.is_ascii_digit())));
	}
	if ["sd", "vd", "hd", "xvd"].iter().any(|prefix| name.starts_with(prefix)) {
		return !ends_in_digit;
	}
	true
}

impl Parse for Disks {
	const FILE: &'static str = "proc/diskstats";

	fn parse(text: &str) -> Result<Self, Unread> {
		let mut disks = Vec::new();
		for (number, line) in lines(text) {
			let words: Vec<&str> = line.split_whitespace().collect();
			if words.is_empty() {
				continue;
			}
			let [major, minor, name, rest @ ..] = words.as_slice() else {
				return Err(malformed(Self::FILE, number, EXPECTED));
			};
			if counter(major).is_none() || counter(minor).is_none() {
				return Err(malformed(Self::FILE, number, EXPECTED));
			}
			if !whole(name) {
				continue;
			}
			let values: Option<Vec<u64>> = rest.iter().map(|word| counter(word)).collect();
			let Some([reads, _, read_sectors, _, writes, _, written_sectors, ..]) = values.as_deref()
			else {
				return Err(malformed(Self::FILE, number, EXPECTED));
			};
			let bytes = |sectors: &u64| {
				sectors
					.checked_mul(SECTOR)
					.ok_or_else(|| malformed(Self::FILE, number, "a count of sectors that fits"))
			};
			disks.push(Disk {
				device: (*name).to_owned(),
				reads: *reads,
				read_bytes: bytes(read_sectors)?,
				writes: *writes,
				written_bytes: bytes(written_sectors)?,
			});
		}
		Ok(Self(disks))
	}
}
