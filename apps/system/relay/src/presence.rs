//! Each node's `state`, the relay's own reading of what it holds of it -- live, late, leaving,
//! waiting or gone -- which a page draws and never computes. See spec/architecture/relay.md, "A
//! node says it is leaving before it goes".

use crate::cluster::Held;
use crate::relay::Relay;
use jiff::{SignedDuration, Timestamp};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use std::time::Duration;

/// Heard within this long is live, a round of host's three seconds missed twice and some over.
pub const LIVE: SignedDuration = SignedDuration::from_secs(10);
/// Heard within this long is late; past it, gone.
pub const LATE: SignedDuration = SignedDuration::from_secs(60);
/// How long a relay that has just started shows a peer it has not heard as waiting, not gone.
pub const WAITING: Duration = Duration::from_secs(60);
/// How often a state that time alone changes is looked for, and sent again.
pub const SWEEP: Duration = Duration::from_secs(1);

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Presence {
	Live,
	Late,
	Upgrading,
	Restarting,
	Waiting,
	Gone,
}

/// Why a node said it is going.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Reason {
	Upgrade,
	Restart,
}

impl std::fmt::Display for Reason {
	fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
		formatter.write_str(match self {
			Self::Upgrade => "an upgrade",
			Self::Restart => "a restart",
		})
	}
}

/// What a node's last snapshot says as it goes: why, and in how many seconds it means to be back.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct Leaving {
	pub reason: Reason,
	pub within: u64,
}

/// A node as `/state` and `/live` show it: what is held of it, absent for a peer never heard, and
/// its state.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Entry {
	#[serde(flatten)]
	pub held: Option<Held>,
	pub state: Presence,
}

/// The state of a node held as `held`, or of a peer not yet heard, at `now`, `uptime` into this
/// relay's run.
pub fn presence(held: Option<&Held>, now: Timestamp, uptime: Duration) -> Presence {
	let Some(held) = held else {
		return if uptime < WAITING { Presence::Waiting } else { Presence::Gone };
	};
	let quiet = now.duration_since(held.heard_at);
	if let Some(leaving) = leaving(held)
		&& quiet <= SignedDuration::from_secs(i64::try_from(leaving.within).unwrap_or(i64::MAX))
	{
		return match leaving.reason {
			Reason::Upgrade => Presence::Upgrading,
			Reason::Restart => Presence::Restarting,
		};
	}
	if quiet <= LIVE {
		Presence::Live
	} else if quiet <= LATE {
		Presence::Late
	} else {
		Presence::Gone
	}
}

/// Looks every `every` for a state time alone has changed, for as long as the relay runs.
pub async fn sweep(relay: Arc<Relay>, every: Duration) {
	let mut ticks = tokio::time::interval(every);
	ticks.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
	loop {
		ticks.tick().await;
		relay.sweep();
	}
}

/// What the held snapshot says of its node leaving; one that does not say, or says it in words
/// this relay does not know, says nothing.
fn leaving(held: &Held) -> Option<Leaving> {
	Leaving::deserialize(held.snapshot.get("leaving")?).ok()
}

#[cfg(test)]
mod tests {
	use super::*;
	use serde_json::json;

	fn at(seconds: i64) -> Timestamp {
		Timestamp::from_second(1_790_000_000 + seconds).unwrap()
	}

	fn held(heard: i64, snapshot: serde_json::Value) -> Held {
		Held { version: 1, heard_at: at(heard), snapshot: Arc::new(snapshot) }
	}

	const STARTED: Duration = Duration::from_secs(600);

	#[test]
	fn a_node_is_live_then_late_then_gone_as_it_goes_quiet() {
		let held = held(0, json!({}));
		let state = |seconds| presence(Some(&held), at(seconds), STARTED);
		assert_eq!(state(0), Presence::Live);
		assert_eq!(state(10), Presence::Live);
		assert_eq!(state(11), Presence::Late);
		assert_eq!(state(60), Presence::Late);
		assert_eq!(state(61), Presence::Gone);
	}

	#[test]
	fn a_node_leaving_is_shown_so_within_its_deadline_and_gone_past_it() {
		let upgrade = held(0, json!({ "leaving": { "reason": "upgrade", "within": 180 } }));
		let state = |seconds| presence(Some(&upgrade), at(seconds), STARTED);
		assert_eq!(state(0), Presence::Upgrading);
		assert_eq!(state(180), Presence::Upgrading);
		assert_eq!(state(181), Presence::Gone);

		let restart = held(0, json!({ "leaving": { "reason": "restart", "within": 30 } }));
		assert_eq!(presence(Some(&restart), at(20), STARTED), Presence::Restarting);
		// Past a deadline shorter than a minute, the quiet alone decides.
		assert_eq!(presence(Some(&restart), at(31), STARTED), Presence::Late);
		let unknown = held(0, json!({ "leaving": { "reason": "moving", "within": 30 } }));
		assert_eq!(presence(Some(&unknown), at(0), STARTED), Presence::Live);
	}

	#[test]
	fn a_peer_not_heard_is_waiting_for_the_first_minute_then_gone() {
		assert_eq!(presence(None, at(0), Duration::ZERO), Presence::Waiting);
		assert_eq!(presence(None, at(0), Duration::from_secs(59)), Presence::Waiting);
		assert_eq!(presence(None, at(0), WAITING), Presence::Gone);
	}

	#[test]
	fn an_entry_carries_what_is_held_and_a_peer_not_heard_its_state_alone() {
		let entry = Entry { held: Some(held(0, json!({ "apps": [] }))), state: Presence::Live };
		let written = serde_json::to_value(&entry).unwrap();
		assert_eq!(written["state"], "live");
		assert_eq!(written["version"], 1);
		assert_eq!(written["snapshot"], json!({ "apps": [] }));
		let waiting = Entry { held: None, state: Presence::Waiting };
		assert_eq!(serde_json::to_value(&waiting).unwrap(), json!({ "state": "waiting" }));
	}
}
