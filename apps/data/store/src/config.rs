//! What the store is told by its environment: its own sidecar, as host hands every app declaring
//! `[objects]`, and the backup store it mirrors, as `mise run database mirror-env` writes it. See
//! spec/architecture/objects.md and spec/architecture/databases.md, "Backups are the data, kept off
//! the cluster".

use std::path::PathBuf;

/// The bucket the mirror is kept in, which `service.toml` declares.
pub const BUCKET: &str = "backups";
/// The prefix the database archives under in its store, as `mise run database env` writes
/// `WALG_S3_PREFIX`; the mirror keeps it under the same name.
pub const PREFIX: &str = "database";

/// An S3 endpoint and the key it is asked with.
#[derive(Clone, PartialEq, Eq)]
pub struct Remote {
	pub endpoint: String,
	pub region: String,
	pub access_key_id: String,
	pub secret_access_key: String,
}

impl std::fmt::Debug for Remote {
	fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		formatter.debug_struct("Remote").field("endpoint", &self.endpoint).finish_non_exhaustive()
	}
}

/// The backup store, read with a key that may list and read its bucket and nothing more.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Source {
	pub remote: Remote,
	pub bucket: String,
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum Invalid {
	#[error("{0} is not set")]
	Missing(&'static str),
	#[error("S3_BUCKETS is `{0}`, without `{BUCKET}`, which service.toml declares")]
	NoBucket(String),
}

#[derive(Debug, Clone)]
pub struct Config {
	/// The directory the socket is made in.
	pub data: PathBuf,
	/// This node's own store, the sidecar.
	pub store: Remote,
	/// What the mirror copies from, or why it cannot yet: the store runs without it.
	pub source: Result<Source, Invalid>,
}

impl Config {
	/// Read through `get`, the process environment in production and a map in tests.
	pub fn read(get: impl Fn(&str) -> Option<String>) -> Result<Self, Invalid> {
		let required = |key: &'static str| {
			get(key).filter(|value| !value.trim().is_empty()).ok_or(Invalid::Missing(key))
		};
		let buckets = required("S3_BUCKETS")?;
		if !buckets.split(',').any(|bucket| bucket.trim() == BUCKET) {
			return Err(Invalid::NoBucket(buckets));
		}
		let store = Remote {
			endpoint: required("S3_ENDPOINT")?,
			region: required("S3_REGION")?,
			access_key_id: required("S3_ACCESS_KEY_ID")?,
			secret_access_key: required("S3_SECRET_ACCESS_KEY")?,
		};
		let source = (|| {
			Ok(Source {
				remote: Remote {
					endpoint: required("BACKUP_S3_ENDPOINT")?,
					region: required("BACKUP_S3_REGION")?,
					access_key_id: required("BACKUP_MIRROR_S3_ACCESS_KEY_ID")?,
					secret_access_key: required("BACKUP_MIRROR_S3_SECRET_ACCESS_KEY")?,
				},
				bucket: required("BACKUP_S3_BUCKET")?,
			})
		})();
		let data = get("STORE_DATA").map_or_else(|| PathBuf::from("/data"), PathBuf::from);
		Ok(Self { data, store, source })
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::collections::HashMap;

	fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
		let mut map: HashMap<String, String> = [
			("S3_ENDPOINT", "the-sidecar"),
			("S3_REGION", "us-east-1"),
			("S3_ACCESS_KEY_ID", "local"),
			("S3_SECRET_ACCESS_KEY", "local-secret"),
			("S3_BUCKETS", "backups"),
			("BACKUP_S3_ENDPOINT", "the-backup-store"),
			("BACKUP_S3_REGION", "us-east-005"),
			("BACKUP_S3_BUCKET", "monoflake-backups"),
			("BACKUP_MIRROR_S3_ACCESS_KEY_ID", "reader"),
			("BACKUP_MIRROR_S3_SECRET_ACCESS_KEY", "reader-secret"),
		]
		.into_iter()
		.map(|(k, v)| (k.to_owned(), v.to_owned()))
		.collect();
		for (key, value) in pairs {
			map.insert((*key).to_owned(), (*value).to_owned());
		}
		move |key| map.get(key).cloned()
	}

	#[test]
	fn reads_its_own_store_and_the_source() {
		let config = Config::read(env(&[])).unwrap();
		assert_eq!(config.store.endpoint, "the-sidecar");
		assert_eq!(config.source.as_ref().unwrap().bucket, "monoflake-backups");
		assert_eq!(config.data, PathBuf::from("/data"));
		// No secret in what a log or a panic would print.
		let shown = format!("{config:?}");
		assert!(!shown.contains("secret") && !shown.contains("reader"), "{shown}");
	}

	#[test]
	fn runs_without_a_source_and_never_without_its_own_store() {
		let config = Config::read(env(&[("BACKUP_MIRROR_S3_ACCESS_KEY_ID", "")])).unwrap();
		assert_eq!(config.source, Err(Invalid::Missing("BACKUP_MIRROR_S3_ACCESS_KEY_ID")));
		let read = |pairs: &[(&str, &str)]| Config::read(env(pairs)).unwrap_err();
		assert_eq!(read(&[("S3_ENDPOINT", "")]), Invalid::Missing("S3_ENDPOINT"));
		assert_eq!(read(&[("S3_BUCKETS", "photos,thumbs")]), Invalid::NoBucket("photos,thumbs".into()));
	}
}
