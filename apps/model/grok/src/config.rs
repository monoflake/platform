//! Settings, read from the environment because the program runs in a container
//! (spec/architecture/grok/deployment.md).

use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, Result, bail};

/// 42 twice: Grok is modeled on The Hitchhiker's Guide to the Galaxy, where 42 is the answer.
const DEFAULT_PORT: u16 = 42042;

pub struct Config {
	/// The port listened on, on every interface (spec/architecture/grok/api.md).
	pub port: u16,
	/// The one key every request must carry.
	pub api_key: String,
	/// Where the agent's clean environment and the CLI's state live; a volume in the container.
	pub data_dir: PathBuf,
	pub cli: Cli,
	/// How long a session is kept after it last answered (spec/architecture/grok/sessions.md).
	pub session_idle: Duration,
	pub twitter: Twitter,
}

/// The `/twitter/` endpoints (spec/architecture/grok/twitter.md).
pub struct Twitter {
	/// Answer from the latest result at once and refresh behind, or wait for a fresh one.
	pub fast_response: bool,
	/// The time budget of one request; what was obtained by then is returned.
	pub budget: Duration,
	/// The model only copies what a tool returned, which needs little reasoning.
	pub effort: String,
}

/// Which Grok CLI runs, and who moves it.
pub enum Cli {
	/// One binary, never updated: a development machine's own install.
	Fixed(PathBuf),
	/// Binaries on the volume, updated by grok2api (spec/architecture/grok/deployment.md).
	Managed {
		/// The copy the image carries, installed when the volume has none.
		seed: PathBuf,
		channel: String,
		/// A version to hold to instead of following the channel.
		pin: Option<String>,
		/// How often the target version is looked up.
		interval: Duration,
	},
}

impl Config {
	pub fn from_env() -> Result<Self> {
		Ok(Self {
			port: parse("GROK2API_PORT", DEFAULT_PORT)?,
			api_key: api_key()?,
			data_dir: var("GROK2API_DATA_DIR").unwrap_or_else(|| "data".into()).into(),
			cli: Cli::from_env()?,
			session_idle: Duration::from_secs(parse("GROK2API_SESSION_IDLE_SECS", 24 * 60 * 60)?),
			twitter: Twitter {
				fast_response: parse("GROK2API_TWITTER_FAST_RESPONSE", true)?,
				budget: Duration::from_secs(parse("GROK2API_TWITTER_TIMEOUT_SECS", 60)?),
				effort: var("GROK2API_TWITTER_EFFORT").unwrap_or_else(|| "low".into()),
			},
		})
	}

	/// What `login` needs: no API key, since it serves nothing.
	pub fn for_login() -> Result<(PathBuf, Cli)> {
		Ok((var("GROK2API_DATA_DIR").unwrap_or_else(|| "data".into()).into(), Cli::from_env()?))
	}
}

impl Cli {
	fn from_env() -> Result<Self> {
		if let Some(binary) = var("GROK2API_GROK_BIN") {
			return Ok(Self::Fixed(binary.into()));
		}
		Ok(Self::Managed {
			seed: var("GROK2API_GROK_SEED")
				.unwrap_or_else(|| "/usr/local/lib/grok2api/grok".into())
				.into(),
			channel: var("GROK2API_GROK_CHANNEL").unwrap_or_else(|| "stable".into()),
			pin: var("GROK2API_GROK_VERSION"),
			// The stable channel moves weekly, and a check is one small request.
			interval: Duration::from_secs(parse("GROK2API_UPDATE_INTERVAL_SECS", 60 * 60)?),
		})
	}
}

fn api_key() -> Result<String> {
	match var("GROK2API_API_KEY") {
		Some(key) => Ok(key),
		None => bail!("GROK2API_API_KEY is not set; every request is checked against it"),
	}
}

fn var(name: &str) -> Option<String> {
	std::env::var(name).ok().filter(|value| !value.trim().is_empty())
}

fn parse<T: std::str::FromStr>(name: &str, default: T) -> Result<T>
where
	T::Err: std::error::Error + Send + Sync + 'static,
{
	match var(name) {
		Some(value) => value.trim().parse().with_context(|| format!("{name} is not valid: {value}")),
		None => Ok(default),
	}
}
