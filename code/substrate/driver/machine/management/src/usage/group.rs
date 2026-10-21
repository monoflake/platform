//! A control group's files, cgroup v2: `cpu.stat`, `memory.current`, `memory.max`, `io.stat` and
//! `pids.current`.

use super::scan::{counter, lines, malformed, past_end, slurp};
use crate::{Group, ReadGroup, Unread};
use std::path::{Path, PathBuf};

/// Where the hierarchy is mounted, under the root.
const HIERARCHY: &str = "sys/fs/cgroup";

/// A file that holds one number.
fn single(root: &Path, directory: &Path, name: &str) -> Result<u64, Unread> {
	let file = directory.join(name);
	let text = slurp(root, &file)?;
	counter(text.trim()).ok_or_else(|| malformed(&file.to_string_lossy(), 1, "a number"))
}

/// `usage_usec` of `cpu.stat`.
fn cpu(root: &Path, directory: &Path) -> Result<u64, Unread> {
	let file = directory.join("cpu.stat");
	let text = slurp(root, &file)?;
	for (number, line) in lines(&text) {
		let mut words = line.split_whitespace();
		if words.next() == Some("usage_usec") {
			return words
				.next()
				.and_then(counter)
				.ok_or_else(|| malformed(&file.to_string_lossy(), number, "usage_usec and a number"));
		}
	}
	Err(malformed(&file.to_string_lossy(), past_end(&text), "usage_usec"))
}

/// `memory.max`: a number, or `max`.
fn limit(root: &Path, directory: &Path) -> Result<Option<u64>, Unread> {
	let file = directory.join("memory.max");
	let text = slurp(root, &file)?;
	match text.trim() {
		"max" => Ok(None),
		word => counter(word)
			.map(Some)
			.ok_or_else(|| malformed(&file.to_string_lossy(), 1, "a number or max")),
	}
}

/// The bytes `io.stat` counts read and written, summed over the devices of its lines.
fn io(root: &Path, directory: &Path) -> Result<(u64, u64), Unread> {
	let file = directory.join("io.stat");
	let text = slurp(root, &file)?;
	let expected = "a major:minor device, then rbytes= and wbytes= among its counters";
	let (mut read, mut written) = (0_u64, 0_u64);
	for (number, line) in lines(&text) {
		if line.trim().is_empty() {
			continue;
		}
		let mut words = line.split_whitespace();
		let device = words.next().unwrap_or("");
		let (mut rbytes, mut wbytes) = (None, None);
		for word in words {
			match word.split_once('=') {
				Some(("rbytes", value)) => rbytes = counter(value),
				Some(("wbytes", value)) => wbytes = counter(value),
				Some(_) => {}
				None => return Err(malformed(&file.to_string_lossy(), number, expected)),
			}
		}
		let (Some(rbytes), Some(wbytes)) = (rbytes, wbytes) else {
			return Err(malformed(&file.to_string_lossy(), number, expected));
		};
		if !device.contains(':') {
			return Err(malformed(&file.to_string_lossy(), number, expected));
		}
		read = read.saturating_add(rbytes);
		written = written.saturating_add(wbytes);
	}
	Ok((read, written))
}

impl ReadGroup for Group {
	fn read(root: &Path, path: &Path) -> Result<Self, Unread> {
		let directory = Path::new(HIERARCHY).join(path.strip_prefix("/").unwrap_or(path));
		let (read_bytes, written_bytes) = io(root, &directory)?;
		Ok(Self {
			path: PathBuf::from(path),
			cpu_microseconds: cpu(root, &directory)?,
			memory: single(root, &directory, "memory.current")?,
			memory_limit: limit(root, &directory)?,
			read_bytes,
			written_bytes,
			tasks: single(root, &directory, "pids.current")?,
		})
	}
}
