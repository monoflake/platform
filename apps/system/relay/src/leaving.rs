//! What a relay does as it is stopped on purpose: says why, in a last snapshot of its own that
//! carries `leaving`, and waits a moment for its neighbors to be sent it. See
//! spec/architecture/relay.md, "A node says it is leaving before it goes".

use crate::host::{Event, Reader};
use crate::presence::{Leaving, Reason};
use crate::relay::Relay;
use std::time::Duration;

/// This service's name among host's apps; `service.toml` states it, and a test holds the two.
pub const APP: &str = "relay";

/// How long a relay gives itself to be back: a cloud machine's reboot, `/data` mounted and the
/// health check passed.
pub const WITHIN: Duration = Duration::from_secs(180);

/// How long host is asked why, within the twenty seconds a container is given to stop.
const ASKED: Duration = Duration::from_secs(1);

/// How long the speaking socket to each neighbor has to send the last snapshot.
const TOLD: Duration = Duration::from_secs(2);

/// Why this relay is stopping, by host's newest row for it: a deploy or a rollback still running
/// is an upgrade, and anything else -- a reboot, a stop by hand -- a restart.
pub fn reason(events: &[Event]) -> Reason {
	let upgrading = events.iter().find(|event| event.app == APP).is_some_and(|event| {
		let replacing = matches!(event.action.as_str(), "deploy" | "rollback" | "rollback_with_data");
		replacing && event.outcome == "running"
	});
	if upgrading { Reason::Upgrade } else { Reason::Restart }
}

/// Takes the last snapshot, carrying `leaving`, and waits until every neighbor with a socket open
/// has been sent it, or `TOLD` is up; whether every one was.
pub async fn leave(relay: &Relay, source: &dyn Reader) -> bool {
	let reason = match tokio::time::timeout(ASKED, source.page(None)).await {
		Ok(Ok(events)) => reason(&events),
		Ok(Err(error)) => {
			eprintln!("relay: asking host why it stops: {error}");
			Reason::Restart
		}
		Err(_) => Reason::Restart,
	};
	let neighbors = relay.speaking();
	let version = relay.leave(Leaving { reason, within: WITHIN.as_secs() });
	let told = tokio::time::timeout(TOLD, relay.told_of(&neighbors, version)).await.is_ok();
	let missed = if told { "" } else { ", not every one in time" };
	eprintln!("relay: leaving for {reason}, told {} neighbors{missed}", neighbors.len());
	told
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::host::Source;

	fn event(app: &str, action: &str, outcome: &str) -> Event {
		Event {
			id: 1,
			app: app.into(),
			action: action.into(),
			source: Source { kind: "run".into(), run: Some(1), commit: None },
			image: None,
			outcome: outcome.into(),
			stage: None,
			detail: None,
			started_at: "2026-10-09T12:00:00Z".into(),
			finished_at: None,
		}
	}

	#[test]
	fn a_deploy_or_rollback_of_the_relay_still_running_is_an_upgrade() {
		for action in ["deploy", "rollback", "rollback_with_data"] {
			let events = [event("geo", "restart", "running"), event(APP, action, "running")];
			assert_eq!(reason(&events), Reason::Upgrade, "{action}");
		}
	}

	#[test]
	fn anything_else_is_a_restart() {
		assert_eq!(reason(&[]), Reason::Restart);
		assert_eq!(reason(&[event("geo", "deploy", "running")]), Reason::Restart);
		assert_eq!(reason(&[event(APP, "restart", "running")]), Reason::Restart);
		// Its newest row decides: a deploy finished before an older one still marked running.
		let finished = [event(APP, "deploy", "succeeded"), event(APP, "deploy", "running")];
		assert_eq!(reason(&finished), Reason::Restart);
	}

	#[test]
	fn the_name_is_the_one_the_declaration_states() {
		let declaration = include_str!("../service.toml");
		assert!(declaration.lines().any(|line| line.trim() == format!("name = \"{APP}\"")));
	}
}
