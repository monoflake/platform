//! What the checks have found, shared by the checks, the proxy and `/health`: each member's health
//! and last answer, and the target, which every proxied connection watches for a change.

use crate::check::{self, Health, Target};
use crate::config::Member;
use jiff::Timestamp;
use serde::Serialize;
use std::collections::BTreeMap;
use std::sync::Mutex;
use tokio::sync::watch;

/// One member as `/health` shows it.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Seen {
	pub address: String,
	pub up: bool,
	/// When it last answered at all, whatever it said.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub answered_at: Option<Timestamp>,
	/// Its last answer, `200` or another status, or why there was none.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub last: Option<String>,
	#[serde(skip)]
	pub health: Health,
}

pub struct State {
	members: Mutex<BTreeMap<String, Seen>>,
	target: watch::Sender<Target>,
}

impl State {
	pub fn new(members: &[Member]) -> Self {
		let seen = members
			.iter()
			.map(|member| {
				let seen = Seen {
					address: member.host.clone(),
					up: false,
					answered_at: None,
					last: None,
					health: Health::default(),
				};
				(member.name.clone(), seen)
			})
			.collect();
		Self { members: Mutex::new(seen), target: watch::Sender::new(Target::None) }
	}

	/// One check's outcome for `name`; answers its health after it, so the check knows when to ask
	/// next. A change of target is logged once, here, and reaches every connection watching it.
	pub fn observe(
		&self,
		name: &str,
		answer: Result<u16, String>,
		now: Timestamp,
		timings: &check::Timings,
	) -> Health {
		let mut members = self.members.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
		let Some(seen) = members.get_mut(name) else { return Health::default() };
		let primary = matches!(answer, Ok(200));
		match &answer {
			Ok(status) => {
				seen.answered_at = Some(now);
				seen.last = Some(status.to_string());
			}
			Err(why) => seen.last = Some(why.clone()),
		}
		seen.health = seen.health.observe(primary, timings);
		seen.up = seen.health.up;
		let health = seen.health;
		let target = check::decide(members.iter().map(|(name, seen)| (name.as_str(), seen.health)));
		drop(members);
		self.target.send_if_modified(|current| {
			if *current == target {
				return false;
			}
			eprintln!("primary: target {} -> {}", shown(current), shown(&target));
			*current = target;
			true
		});
		health
	}

	pub fn target(&self) -> Target {
		self.target.borrow().clone()
	}

	pub fn watch(&self) -> watch::Receiver<Target> {
		self.target.subscribe()
	}

	pub fn members(&self) -> BTreeMap<String, Seen> {
		self.members.lock().unwrap_or_else(std::sync::PoisonError::into_inner).clone()
	}
}

fn shown(target: &Target) -> String {
	match target {
		Target::One { member } => member.clone(),
		Target::None => "none: no member answers as primary".into(),
		Target::Many { members } => format!("none: {} all answer as primary", members.join(" and ")),
	}
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::check::PIGSTY;

	fn member(name: &str) -> Member {
		Member { name: name.into(), host: format!("{name}.test"), rest: 8008, postgres: 5432 }
	}

	#[test]
	fn the_target_follows_the_runs_of_answers_and_is_watched() {
		let state = State::new(&[member("tyo"), member("rdu")]);
		let mut watching = state.watch();
		let now = Timestamp::now();
		for _ in 0..3 {
			state.observe("tyo", Ok(200), now, &PIGSTY);
			state.observe("rdu", Ok(503), now, &PIGSTY);
		}
		assert_eq!(state.target(), Target::One { member: "tyo".into() });
		assert!(watching.has_changed().unwrap());
		watching.mark_unchanged();
		// rdu rises while tyo still answers: two, and so nowhere, until tyo falls.
		for _ in 0..3 {
			state.observe("rdu", Ok(200), now, &PIGSTY);
		}
		assert!(matches!(state.target(), Target::Many { .. }));
		for _ in 0..3 {
			state.observe("tyo", Err("connection refused".into()), now, &PIGSTY);
		}
		assert_eq!(state.target(), Target::One { member: "rdu".into() });
		let seen = state.members();
		assert_eq!(seen["tyo"].last.as_deref(), Some("connection refused"));
		assert_eq!(seen["rdu"].last.as_deref(), Some("200"));
		assert!(seen["rdu"].up && !seen["tyo"].up);
	}
}
