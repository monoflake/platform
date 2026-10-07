//! rclone, run by the store for the mirror: both remotes given on its environment, never on its
//! command line or in a file, and never asked anything a bucket answers -- a listing or a read of
//! keys under the prefix is all the source's key may do.

use crate::config::Remote;
use crate::mirror::{self, Listing};
use std::process::Stdio;
use tokio::process::Command;

/// rclone's exit status for a directory that is not there: a prefix nothing was ever written under.
const NOT_FOUND: i32 = 3;

#[derive(Debug, thiserror::Error)]
pub enum Error {
	#[error("rclone could not be started: {0}")]
	Spawn(std::io::Error),
	#[error("rclone {verb} failed: {detail}")]
	Failed { verb: &'static str, detail: String },
	#[error("rclone's listing was unreadable: {0}")]
	Unreadable(#[from] serde_json::Error),
}

pub struct Rclone {
	program: String,
	env: Vec<(String, String)>,
}

/// One remote as rclone's environment names it: an S3 that is neither Amazon's nor checked for, so
/// no bucket is created or asked after, and addressed by path.
fn remote(name: &str, remote: &Remote) -> Vec<(String, String)> {
	let key = |field: &str| format!("RCLONE_CONFIG_{name}_{field}");
	vec![
		(key("TYPE"), "s3".into()),
		(key("PROVIDER"), "Other".into()),
		(key("ENDPOINT"), remote.endpoint.clone()),
		(key("REGION"), remote.region.clone()),
		(key("ACCESS_KEY_ID"), remote.access_key_id.clone()),
		(key("SECRET_ACCESS_KEY"), remote.secret_access_key.clone()),
		(key("NO_CHECK_BUCKET"), "true".into()),
		(key("FORCE_PATH_STYLE"), "true".into()),
	]
}

impl Rclone {
	/// `source:` and `mirror:`, the two remotes every command here names.
	pub fn new(program: &str, source: &Remote, mirror: &Remote) -> Self {
		// Its cache, were it to want one, in the container's scratch.
		let mut env = vec![("HOME".to_owned(), "/tmp".to_owned())];
		env.extend(remote("SOURCE", source));
		env.extend(remote("MIRROR", mirror));
		Self { program: program.to_owned(), env }
	}

	fn command(&self, args: &[&str]) -> Command {
		let mut command = Command::new(&self.program);
		command
			.env_clear()
			.envs(self.env.iter().cloned())
			// No configuration file: every remote is in the environment.
			.args(["--config", "", "--retries", "3", "--low-level-retries", "5", "--contimeout", "10s"])
			.args(["--timeout", "60s"])
			.args(args)
			.stdin(Stdio::null())
			.stdout(Stdio::piped())
			.stderr(Stdio::piped());
		command
	}

	/// Run to the end; the exit code with what it printed, its errors written to the log.
	async fn run(&self, verb: &'static str, args: &[&str]) -> Result<(i32, String), Error> {
		let out = self.command(args).output().await.map_err(Error::Spawn)?;
		let errors = String::from_utf8_lossy(&out.stderr);
		if !errors.trim().is_empty() {
			eprint!("{errors}");
		}
		let code = out.status.code().unwrap_or(-1);
		if code != 0 && code != NOT_FOUND {
			let last = errors.lines().rev().find(|line| !line.trim().is_empty()).unwrap_or("");
			return Err(Error::Failed { verb, detail: format!("{}: {last}", out.status) });
		}
		Ok((code, String::from_utf8_lossy(&out.stdout).into_owned()))
	}

	/// Every object under `path`, or None when nothing is.
	pub async fn list(&self, path: &str) -> Result<Option<Listing>, Error> {
		let args = ["lsjson", "--recursive", "--files-only", "--no-mimetype", "--no-modtime"];
		let (code, out) = self.run("lsjson", &[&args[..], &["--fast-list", path]].concat()).await?;
		if code == NOT_FOUND {
			return Ok(None);
		}
		Ok(Some(mirror::listing(&out)?))
	}

	/// `to` made to hold what `from` does and nothing else. Compared by checksum where both sides
	/// have one and by size where not, so a `metadata.json` that `backup-mark` rewrote is copied
	/// again; rclone deletes nothing in a run that met any error.
	pub async fn sync(&self, from: &str, to: &str) -> Result<(), Error> {
		let flags = ["--checksum", "--fast-list", "--transfers", "4", "--checkers", "8"];
		let (code, _) = self.run("sync", &[&["sync", from, to][..], &flags].concat()).await?;
		if code == NOT_FOUND {
			return Err(Error::Failed { verb: "sync", detail: format!("{from} is not there") });
		}
		Ok(())
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn remote_named(endpoint: &str) -> Remote {
		Remote {
			endpoint: endpoint.into(),
			region: "us-east-1".into(),
			access_key_id: "id".into(),
			secret_access_key: "secret".into(),
		}
	}

	#[test]
	fn both_remotes_are_in_the_environment_and_none_on_the_line() {
		let rclone = Rclone::new("rclone", &remote_named("the-source"), &remote_named("the-mirror"));
		let command = rclone.command(&["lsjson", "source:bucket/database"]);
		let std = command.as_std();
		let args: Vec<String> = std.get_args().map(|a| a.to_string_lossy().into_owned()).collect();
		assert!(!args.iter().any(|arg| arg.contains("secret")), "{args:?}");
		let env: std::collections::HashMap<String, String> = std
			.get_envs()
			.filter_map(|(k, v)| {
				Some((k.to_string_lossy().into_owned(), v?.to_string_lossy().into_owned()))
			})
			.collect();
		assert_eq!(env["RCLONE_CONFIG_SOURCE_ENDPOINT"], "the-source");
		assert_eq!(env["RCLONE_CONFIG_MIRROR_ENDPOINT"], "the-mirror");
		assert_eq!(env["RCLONE_CONFIG_SOURCE_NO_CHECK_BUCKET"], "true");
		assert_eq!(env["RCLONE_CONFIG_SOURCE_SECRET_ACCESS_KEY"], "secret");
	}
}
