//! The mirror job: the database's backups copied from the backup store into this node's, deletions
//! included, and never from a source that answered nothing. See spec/architecture/databases.md,
//! "Backups are the data, kept off the cluster".

use crate::config::{BUCKET, Config, Invalid, PREFIX};
use crate::mirror::{self, Refused, Report};
use crate::rclone::{self, Rclone};

/// How many of the objects a sync left out a failure names.
const SHOWN: usize = 5;

pub struct Store {
	pub config: Config,
	/// rclone's path: the image's own, or `RCLONE` where it is elsewhere.
	pub program: String,
	/// Held while a mirror runs, so a second is refused rather than run beside it.
	pub mirroring: tokio::sync::Mutex<()>,
}

#[derive(Debug, thiserror::Error)]
pub enum Unmirrored {
	#[error("the backup store is not configured: {0}")]
	Unconfigured(Invalid),
	#[error(transparent)]
	Refused(#[from] Refused),
	#[error(transparent)]
	Rclone(#[from] rclone::Error),
	#[error("the mirror lacks {count} of the source's objects after the sync, among them {named:?}")]
	Incomplete { count: usize, named: Vec<String> },
}

impl Store {
	pub fn new(config: Config) -> Self {
		let program = std::env::var("RCLONE").unwrap_or_else(|_| "/usr/local/bin/rclone".into());
		Self { config, program, mirroring: tokio::sync::Mutex::new(()) }
	}

	/// Both listed, the guard asked, the sync run, and the mirror listed again to see that it holds
	/// everything the source did.
	pub async fn mirror(&self) -> Result<Report, Unmirrored> {
		let source =
			self.config.source.as_ref().map_err(|why| Unmirrored::Unconfigured(why.clone()))?;
		let rclone = Rclone::new(&self.program, &source.remote, &self.config.store);
		let from = format!("source:{}/{PREFIX}", source.bucket);
		let to = format!("mirror:{BUCKET}/{PREFIX}");
		let listed = rclone.list(&from).await?.unwrap_or_default();
		let before = rclone.list(&to).await?.unwrap_or_default();
		mirror::guard(&listed, &before)?;
		rclone.sync(&from, &to).await?;
		let after = rclone.list(&to).await?.unwrap_or_default();
		let (count, named) = mirror::missing(&listed, &after, SHOWN);
		if count > 0 {
			return Err(Unmirrored::Incomplete { count, named });
		}
		Ok(Report::new(&listed, &before, &after))
	}
}
