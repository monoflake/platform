//! The clean environment the agent runs in. Most of what the CLI puts around a prompt is a coding
//! agent's context, and this is what takes it away; spec/architecture/grok/bridge.md, "The agent is
//! a coding agent".

use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use tokio::process::Command;

/// An agent definition sessions are created with, written into GROK_HOME at every start.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Profile {
	/// Chat: one tool, never useful, because an empty or unknown `tools` list gives the full set.
	Chat,
	/// X: the full set less everything but xAI's server-side `x_search`
	/// (spec/architecture/grok/twitter.md).
	Twitter,
}

impl Profile {
	pub const ALL: [Self; 2] = [Self::Chat, Self::Twitter];

	pub fn name(self) -> &'static str {
		match self {
			Self::Chat => "grok2api",
			Self::Twitter => "grok2api-twitter",
		}
	}

	fn definition(self) -> &'static str {
		match self {
			Self::Chat => CHAT_PROFILE,
			Self::Twitter => TWITTER_PROFILE,
		}
	}
}

const CHAT_PROFILE: &str = "---
name: grok2api
description: Plain chat for grok2api. No tools.
tools: search_tool
agents_md: false
---

You are a helpful assistant.
";

/// `x_search` cannot be allowed by name -- an allowlist does not recognize it and falls back to
/// every tool -- so everything else is denied instead. The key is camel case; `disallowed_tools` is
/// ignored. The shell is `run_terminal_cmd` to the denylist, whatever the tool list calls it. Only
/// tools the clean environment has are named, since each name that matches nothing is a warning on
/// every session. A tool a newer CLI adds is not on this list; the startup check's bound on tool
/// definitions is what notices it.
const TWITTER_PROFILE: &str = "---
name: grok2api-twitter
description: X data for grok2api. X search only.
disallowedTools: run_terminal_cmd,read_file,search_replace,list_dir,grep,todo_write,scheduler_create,scheduler_delete,scheduler_list,monitor,use_tool,update_goal,enter_plan_mode,exit_plan_mode,ask_user_question,web_search,web_fetch,image_gen,image_edit,image_to_video,reference_to_video,write,Agent
agents_md: false
---

You read X with your X tools.
";

/// Read by grok's log filter: warnings, plus the per-session context breakdown the startup
/// check reads. Plain `info` logs every streamed token.
const AGENT_LOG_FILTER: &str = "warn,[session.context_snapshot]=info";

/// Passed through from this process to the agent; everything else is withheld, so nothing the
/// host sets -- an API key, a GROK_* switch -- changes what the agent does.
const PASSED_THROUGH: &[&str] = &[
	"PATH",
	"LANG",
	"TZ",
	"SSL_CERT_FILE",
	"SSL_CERT_DIR",
	"HTTP_PROXY",
	"HTTPS_PROXY",
	"NO_PROXY",
	"http_proxy",
	"https_proxy",
	"no_proxy",
];

pub struct Environment {
	/// The agent's HOME, empty on purpose: discovery of ~/.claude, ~/.cursor and their plugins
	/// keys off it, and nothing else turns plugin discovery off.
	pub home: PathBuf,
	/// The CLI's own state, credentials included.
	pub grok_home: PathBuf,
	/// The working directory sessions are created in, also empty.
	pub workspace: PathBuf,
	/// The CLI binaries grok2api manages (spec/architecture/grok/deployment.md).
	pub cli: PathBuf,
	/// X answers that can no longer change (spec/architecture/grok/twitter.md); deleting it clears
	/// them.
	pub twitter: PathBuf,
}

impl Environment {
	pub fn prepare(data_dir: &Path) -> Result<Self> {
		let root = absolute(data_dir)?;
		let environment = Self {
			home: root.join("home"),
			grok_home: root.join("grok"),
			workspace: root.join("workspace"),
			cli: root.join("cli"),
			twitter: root.join("twitter"),
		};
		for dir in [&environment.home, &environment.grok_home, &environment.workspace] {
			std::fs::create_dir_all(dir).with_context(|| format!("cannot create {}", dir.display()))?;
		}
		let agents = environment.grok_home.join("agents");
		std::fs::create_dir_all(&agents)?;
		for profile in Profile::ALL {
			std::fs::write(agents.join(format!("{}.md", profile.name())), profile.definition())?;
		}
		Ok(environment)
	}

	/// `grok agent stdio`, with the environment cleared and set to the one above.
	pub fn agent_command(&self, grok_bin: &Path) -> Command {
		let mut command = self.command(grok_bin);
		command
			.args(["agent", "stdio"])
			.env("GROK_WORKFLOWS", "0")
			.env("GROK_SUBAGENTS", "0")
			.env("GROK_MEMORY", "0")
			// grok2api runs the update cycle itself; spec/architecture/grok/deployment.md.
			.env("GROK_DISABLE_AUTOUPDATER", "1")
			.env("RUST_LOG", AGENT_LOG_FILTER);
		command
	}

	/// `grok login` by device code, which needs no browser where it runs, into this environment's
	/// GROK_HOME. The CLI does the signing in; grok2api only starts it
	/// (spec/architecture/grok/bridge.md).
	pub fn login_command(&self, grok_bin: &Path) -> Command {
		let mut command = self.command(grok_bin);
		command.args(["login", "--device-auth"]);
		command
	}

	fn command(&self, grok_bin: &Path) -> Command {
		let mut command = Command::new(grok_bin);
		command.current_dir(&self.workspace).env_clear();
		for name in PASSED_THROUGH {
			if let Ok(value) = std::env::var(name) {
				command.env(name, value);
			}
		}
		command.env("HOME", &self.home).env("GROK_HOME", &self.grok_home);
		command
	}
}

fn absolute(path: &Path) -> Result<PathBuf> {
	std::fs::create_dir_all(path).with_context(|| format!("cannot create {}", path.display()))?;
	path.canonicalize().with_context(|| format!("cannot resolve {}", path.display()))
}
