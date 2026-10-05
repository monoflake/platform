//! The startup check that the clean environment applied. Two of its failures are silent inside the
//! agent, so a start that cannot prove it is a failed start; spec/architecture/grok/bridge.md, "A
//! clean environment is checked, not assumed".

use std::time::Duration;

use anyhow::{Result, bail};
use tokio::sync::mpsc;

use crate::agent::Agent;
use crate::environment::{Environment, Profile};

/// The profile's tool definitions measured 698 tokens and the default agent's 8.8k; the bound
/// sits well between, so a CLI release that grows the one kept tool still passes and a profile
/// that failed to apply never does.
const MAX_TOOL_TOKENS: u64 = 3000;

/// How long to wait for the breakdown once a session exists; it measured about 0.3 s.
const SNAPSHOT_TIMEOUT: Duration = Duration::from_secs(15);

#[derive(Debug, PartialEq)]
pub struct Snapshot {
	pub skills: u64,
	pub system_prompt: u64,
	pub tool_definitions: u64,
	pub mcp: u64,
	pub agents_md: u64,
	pub workflows: u64,
}

impl Snapshot {
	/// Reads `session_context_snapshot: emitted ... skills_tokens=1988 ...` from a log line.
	pub fn parse(line: &str) -> Option<Self> {
		let rest = &line[line.find("session_context_snapshot: emitted")?..];
		let field = |name: &str| -> Option<u64> {
			let start = rest.find(&format!("{name}="))? + name.len() + 1;
			rest[start..].split(|c: char| !c.is_ascii_digit()).next()?.parse().ok()
		};
		Some(Self {
			skills: field("skills_tokens")?,
			system_prompt: field("system_prompt_tokens")?,
			tool_definitions: field("tool_definitions_tokens")?,
			mcp: field("mcp_tokens")?,
			agents_md: field("agents_md_tokens")?,
			workflows: field("workflows_tokens")?,
		})
	}

	/// What in the breakdown says the isolation leaked, if anything.
	pub fn leaks(&self) -> Vec<String> {
		let mut leaks = Vec::new();
		for (name, tokens) in
			[("mcp", self.mcp), ("agents_md", self.agents_md), ("workflows", self.workflows)]
		{
			if tokens > 0 {
				leaks.push(format!("{name} context is {tokens} tokens, expected none"));
			}
		}
		if self.tool_definitions > MAX_TOOL_TOKENS {
			leaks.push(format!(
				"tool definitions are {} tokens, over {MAX_TOOL_TOKENS}: the profile did not apply",
				self.tool_definitions
			));
		}
		leaks
	}
}

/// Opens one session, reads its breakdown, and closes it again. No prompt is sent, so the check
/// costs nothing against the subscription.
pub async fn run(
	agent: &Agent,
	environment: &Environment,
	profile: Profile,
	log: &mut mpsc::UnboundedReceiver<String>,
) -> Result<Snapshot> {
	while log.try_recv().is_ok() {}
	let session_id = agent.new_session(&environment.workspace, profile, "startup check").await?;
	let snapshot = tokio::time::timeout(SNAPSHOT_TIMEOUT, async {
		while let Some(line) = log.recv().await {
			if line.contains("Failed to parse agent definition") {
				return Err(anyhow::anyhow!("the agent profile did not parse: {line}"));
			}
			// An allowlist naming a tool the CLI does not know falls back to every tool.
			if line.contains("keeping full grok toolset") {
				return Err(anyhow::anyhow!("the agent profile named an unknown tool: {line}"));
			}
			if let Some(snapshot) = Snapshot::parse(&line) {
				return Ok(snapshot);
			}
		}
		bail!("the agent exited before reporting its context")
	})
	.await;
	agent.close(&session_id).await;
	let snapshot = match snapshot {
		Ok(result) => result?,
		Err(_) => bail!("the agent reported no context breakdown within {SNAPSHOT_TIMEOUT:?}"),
	};
	let leaks = snapshot.leaks();
	if !leaks.is_empty() {
		bail!("the clean environment leaked for {}: {}", profile.name(), leaks.join("; "));
	}
	Ok(snapshot)
}

#[cfg(test)]
mod tests {
	use super::Snapshot;

	const CLEAN: &str = "2026-09-27T10:00:07.741138Z  INFO session.context_snapshot: session_context_snapshot: emitted model=\"grok-4.6\" skills_tokens=1988 system_prompt_tokens=1 tool_definitions_tokens=698 mcp_tokens=0 agents_md_tokens=0 workflows_tokens=0 skills_count=19";

	#[test]
	fn reads_a_clean_breakdown() {
		let snapshot = Snapshot::parse(CLEAN).unwrap();
		assert_eq!(snapshot.tool_definitions, 698);
		assert!(snapshot.leaks().is_empty());
	}

	#[test]
	fn a_default_agent_is_a_leak() {
		let line = CLEAN.replace("tool_definitions_tokens=698", "tool_definitions_tokens=8831");
		assert_eq!(Snapshot::parse(&line).unwrap().leaks().len(), 1);
	}

	#[test]
	fn ignores_other_lines() {
		assert!(Snapshot::parse("session_context_snapshot: tokenizing model=\"grok-4.6\"").is_none());
	}
}
