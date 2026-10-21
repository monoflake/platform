//! A binding's share of btrfs held by simple quotas, by the `btrfs` command, RFC vr5lw.
//! https://btrfs.readthedocs.io/en/latest/btrfs-qgroup.html

use std::ffi::OsStr;
use std::path::Path;

use crate::{Btrfs, Fault, Quota};

impl Btrfs {
	/// The command run, and what it wrote, or what it wrote to its error when it failed.
	async fn run(&self, args: &[&OsStr]) -> Result<String, Fault> {
		let shown = || {
			let words: Vec<_> = args.iter().map(|a| a.to_string_lossy()).collect();
			format!("btrfs {}", words.join(" "))
		};
		let output = tokio::process::Command::new(&self.binary)
			.args(args)
			.output()
			.await
			.map_err(|e| Fault(format!("{}: {e}", shown())))?;
		if output.status.success() {
			Ok(String::from_utf8_lossy(&output.stdout).into_owned())
		} else {
			Err(Fault(format!("{}: {}", shown(), String::from_utf8_lossy(&output.stderr).trim())))
		}
	}
}

/// A subvolume's own qgroup, `0/<its id>`, from what `btrfs inspect-internal rootid` writes.
fn own_qgroup(rootid: &str) -> Result<String, Fault> {
	let id: u64 =
		rootid.trim().parse().map_err(|_| Fault(format!("btrfs rootid wrote {rootid:?}")))?;
	Ok(format!("0/{id}"))
}

impl Quota for Btrfs {
	async fn assign(&self, subvolume: &Path, qgroup: &str) -> Result<(), Fault> {
		let rootid =
			self.run(&["inspect-internal".as_ref(), "rootid".as_ref(), subvolume.as_os_str()]).await?;
		let own = own_qgroup(&rootid)?;
		self
			.run(&[
				"qgroup".as_ref(),
				"assign".as_ref(),
				own.as_ref(),
				qgroup.as_ref(),
				self.mount.as_os_str(),
			])
			.await?;
		Ok(())
	}

	async fn limit(&self, qgroup: &str, bytes: Option<u64>) -> Result<(), Fault> {
		let size = bytes.map_or_else(|| "none".to_owned(), |b| b.to_string());
		self
			.run(&[
				"qgroup".as_ref(),
				"limit".as_ref(),
				size.as_ref(),
				qgroup.as_ref(),
				self.mount.as_os_str(),
			])
			.await?;
		Ok(())
	}
}

#[cfg(test)]
mod tests {
	use super::own_qgroup;

	#[test]
	fn a_subvolume_is_its_own_qgroup_at_level_zero() {
		assert_eq!(own_qgroup("258\n").unwrap(), "0/258");
		assert!(own_qgroup("ERROR: not a btrfs filesystem").is_err());
	}
}
