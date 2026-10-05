mod agent;
mod anthropic;
mod check;
mod cli;
mod config;
mod environment;
mod http;
mod message;
mod openai;
mod responses;
mod sessions;
mod transcript;
mod turn;
mod twitter;
mod update;

use std::io::IsTerminal;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

use anyhow::{Context, Result, bail};
use tracing_subscriber::EnvFilter;

use crate::cli::Binaries;
use crate::config::{Cli, Config};
use crate::environment::Environment;
use crate::turn::Bridge;
use crate::update::Updater;

/// How often idle sessions are looked at for expiry.
const EXPIRY_SWEEP: Duration = Duration::from_secs(60);

const USAGE: &str = "usage: grok2api [login]

  (no argument)  serve the API
  login          sign the CLI in, by device code, into GROK2API_DATA_DIR";

#[tokio::main]
async fn main() -> Result<()> {
	tracing_subscriber::fmt()
		.with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
		// Color codes only where something renders them; a container's log collector does not.
		.with_ansi(std::io::stdout().is_terminal())
		.init();
	match std::env::args().nth(1).as_deref() {
		None | Some("serve") => serve().await,
		Some("login") => login().await,
		Some(_) => {
			eprintln!("{USAGE}");
			std::process::exit(2);
		}
	}
}

async fn serve() -> Result<()> {
	let config = Config::from_env()?;
	let environment = Environment::prepare(&config.data_dir)?;
	let (binary, updater) = match config.cli {
		Cli::Fixed(binary) => (binary, None),
		Cli::Managed { seed, channel, pin, interval } => {
			let binaries = Binaries::new(environment.cli.clone())?;
			let version = binaries.initial(&seed).await?;
			binaries.prune(&[&version]);
			(binaries.path(&version), Some((binaries, channel, pin, interval)))
		}
	};
	let agent = update::launch_when_signed_in(&environment, &binary)
		.await
		.context("the agent is not fit to serve")?;
	tracing::info!(version = %agent.info.version, models = ?agent.info.models, "agent ready");

	let bridge = Arc::new(Bridge::new(agent, environment, config.session_idle));
	let twitter = Arc::new(
		twitter::Service::new(bridge.clone(), &config.twitter).context("cannot keep X answers")?,
	);
	let (sessions, latest) = (bridge.clone(), twitter.clone());
	tokio::spawn(async move {
		let mut interval = tokio::time::interval(EXPIRY_SWEEP);
		loop {
			interval.tick().await;
			sessions.expire().await;
			latest.sweep();
		}
	});
	if let Some((binaries, channel, pin, interval)) = updater {
		tracing::info!(channel, pin = ?pin, "the CLI is updated by grok2api");
		tokio::spawn(Updater { bridge: bridge.clone(), binaries, channel, pin, interval }.run());
	}

	let listener = tokio::net::TcpListener::bind(("0.0.0.0", config.port))
		.await
		.with_context(|| format!("cannot listen on port {}", config.port))?;
	tracing::info!(port = config.port, "listening on every interface");
	axum::serve(listener, http::router(bridge, twitter, config.api_key)).await?;
	Ok(())
}

/// Runs the CLI's own device-code sign-in against the environment the server uses.
async fn login() -> Result<()> {
	let (data_dir, cli) = Config::for_login()?;
	let environment = Environment::prepare(&data_dir)?;
	let binary: PathBuf = match cli {
		Cli::Fixed(binary) => binary,
		Cli::Managed { seed, .. } => {
			let binaries = Binaries::new(environment.cli.clone())?;
			let version = binaries.initial(&seed).await?;
			binaries.path(&version)
		}
	};
	let status = environment.login_command(&binary).status().await?;
	if !status.success() {
		bail!("grok login exited with {status}");
	}
	println!("Signed in. A server waiting for sign-in picks it up within a few seconds.");
	Ok(())
}
