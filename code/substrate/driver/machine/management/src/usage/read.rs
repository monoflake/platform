//! A machine's usage read whole, under a root.

use super::scan::slurp;
use crate::{Disks, Interfaces, Load, Memory, Parse, Processor, ReadUsage, Space, Unread, Usage};
use std::path::{Path, PathBuf};

/// What the `T` file holds, under `root`, read.
fn file<T: Parse>(root: &Path) -> Result<T, Unread> {
	T::parse(&slurp(root, Path::new(T::FILE))?)
}

impl ReadUsage for Usage {
	fn read(root: &Path, mounts: &[PathBuf], at: u64) -> Result<Self, Unread> {
		Ok(Self {
			at,
			processor: file::<Processor>(root)?,
			load: file::<Load>(root)?,
			memory: file::<Memory>(root)?,
			disks: file::<Disks>(root)?,
			interfaces: file::<Interfaces>(root)?,
			spaces: mounts.iter().map(|mount| Space::of(root, mount)).collect::<Result<_, _>>()?,
		})
	}
}
