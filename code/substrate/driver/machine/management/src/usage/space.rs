//! A file system's space, as `statvfs` gives it for a mount point.

use crate::{Space, Unread};
use rustix::fs::statvfs;
use std::path::{Path, PathBuf};

impl Space {
	/// The space of `mount`, a mount point under `root`, in bytes.
	pub(super) fn of(root: &Path, mount: &Path) -> Result<Self, Unread> {
		let relative = mount.strip_prefix("/").unwrap_or(mount);
		let stat = statvfs(root.join(relative)).map_err(|error| Unread::Missing {
			file: relative.to_path_buf(),
			error: error.to_string(),
		})?;
		let bytes = |blocks: u64| {
			blocks.checked_mul(stat.f_frsize).ok_or_else(|| Unread::Missing {
				file: relative.to_path_buf(),
				error: "a size that does not fit in 64 bits".to_owned(),
			})
		};
		Ok(Self {
			path: PathBuf::from(mount),
			total: bytes(stat.f_blocks)?,
			free: bytes(stat.f_bfree)?,
			available: bytes(stat.f_bavail)?,
		})
	}
}
