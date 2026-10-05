//! Starting an agent that is fit to serve, and moving to a newer CLI while serving. See
//! spec/architecture/grok/deployment.md, "grok2api does the updating, not the CLI".

use std::collections::HashSet;
use std::path::Path;
use std::sync::Arc;
use std::time::Duration;

use anyhow::Result;

use crate::agent::Agent;
use crate::check;
use crate::cli::{self, Binaries};
use crate::environment::{Environment, Profile};
use crate::turn::Bridge;

/// How often a signed-out start looks again, waiting for `grok2api login`.
const SIGN_IN_POLL: Duration = Duration::from_secs(15);

/// The agent has no credentials; distinct from every other failure because it is waited out.
#[derive(Debug)]
pub struct SignedOut;

impl std::fmt::Display for SignedOut {
	fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		f.write_str("the agent is not signed in")
	}
}

impl std::error::Error for SignedOut {}

/// Starts an agent on `binary`, and returns it only once it is signed in and its environment
/// passes the check.
pub async fn launch(environment: &Environment, binary: &Path) -> Result<Arc<Agent>> {
	let (agent, mut log) = Agent::start(environment, binary).await?;
	if !agent.info.signed_in {
		return Err(SignedOut.into());
	}
	for profile in Profile::ALL {
		let snapshot = check::run(&agent, environment, profile, &mut log).await?;
		tracing::info!(version = %agent.info.version, profile = profile.name(), ?snapshot, "clean environment verified");
	}
	// The check needed the log; nothing reads it from here on.
	tokio::spawn(async move { while log.recv().await.is_some() {} });
	Ok(agent)
}

/// `launch`, waiting as long as it takes for somebody to sign in. Signing in is done once per
/// volume, by `grok2api login` in the running container, so a signed-out start stays up for it.
pub async fn launch_when_signed_in(environment: &Environment, binary: &Path) -> Result<Arc<Agent>> {
	loop {
		match launch(environment, binary).await {
			Err(error) if error.is::<SignedOut>() => {
				tracing::warn!("the agent is not signed in; run `grok2api login` where this runs");
				tokio::time::sleep(SIGN_IN_POLL).await;
			}
			outcome => return outcome,
		}
	}
}

pub struct Updater {
	pub bridge: Arc<Bridge>,
	pub binaries: Binaries,
	pub channel: String,
	pub pin: Option<String>,
	pub interval: Duration,
}

impl Updater {
	pub async fn run(self) {
		let client = reqwest::Client::new();
		let mut rejected = HashSet::new();
		let mut interval = tokio::time::interval(self.interval);
		loop {
			interval.tick().await;
			if let Err(error) = self.step(&client, &mut rejected).await {
				tracing::warn!(%error, "the CLI update check failed");
			}
		}
	}

	async fn step(&self, client: &reqwest::Client, rejected: &mut HashSet<String>) -> Result<()> {
		let target = match &self.pin {
			Some(version) => version.clone(),
			None => cli::channel_version(client, &self.channel).await?,
		};
		let current = self.bridge.agent().info.version.clone();
		if target == current || rejected.contains(&target) {
			return Ok(());
		}
		tracing::info!(from = %current, to = %target, "trying another CLI");
		let binary = self.binaries.download(client, &target).await?;
		match launch(&self.bridge.environment, &binary).await {
			Ok(agent) => {
				self.bridge.replace(agent);
				self.binaries.mark_good(&target)?;
				// The replaced agent keeps its binary while its sessions finish.
				self.binaries.prune(&[&target, &current]);
				tracing::info!(version = %target, "new sessions now go to the new CLI");
			}
			Err(error) => {
				tracing::error!(version = %target, %error, "the new CLI failed its check; staying on {current}");
				rejected.insert(target.clone());
				if self.binaries.good().as_deref() != Some(target.as_str()) {
					self.binaries.remove(&target);
				}
			}
		}
		Ok(())
	}
}
