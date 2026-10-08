//! Which member is the primary, as Patroni's REST says and HAProxy would read it: each member is up
//! or down by a run of answers, never by one, and the target is the one member up -- none when
//! none is, and none when two are, since a second primary is a split the proxy must not choose in.
//! The timings are Pigsty v4.5.0's, each naming the file in that repository it came from. See
//! spec/todo/todo.md, "The database".

use serde::Serialize;
use std::time::Duration;

/// How a member is checked and how connections are kept.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timings {
	/// Between checks of a member that is up and steady: `inter`.
	pub inter: Duration,
	/// Between checks of a member on its way up or down: `fastinter`.
	pub fastinter: Duration,
	/// Between checks of a member that is down: `downinter`.
	pub downinter: Duration,
	/// Answers in a row that put a member up, and failures in a row that put it down.
	pub rise: u32,
	pub fall: u32,
	/// How long one check, and one attempt to reach the primary, may take.
	pub check_timeout: Duration,
	pub connect_timeout: Duration,
	/// Attempts to reach the primary after the first fails.
	pub retries: u32,
	/// How long a proxied connection may carry nothing either way before it is closed.
	pub idle: Duration,
	/// Connections proxied at once, and how many may wait for one to end, and for how long.
	pub maxconn: usize,
	pub maxqueue: usize,
	pub queue_timeout: Duration,
}

/// Pigsty's: `pg_rto_plan`'s `norm` row in roles/pgsql/defaults/main.yml for `inter`, `fastinter`,
/// `downinter`, `rise` and `fall`; roles/haproxy/templates/haproxy.cfg.j2's `defaults` for `timeout
/// check`, `timeout connect`, `retries` and `timeout queue`; roles/haproxy/defaults/main.yml's
/// `haproxy_client_timeout` and `haproxy_server_timeout` for `idle`; and
/// roles/pgsql/templates/service.cfg's `default-server` for `maxconn` and `maxqueue`.
pub const PIGSTY: Timings = Timings {
	inter: Duration::from_secs(2),
	fastinter: Duration::from_secs(1),
	downinter: Duration::from_secs(2),
	rise: 3,
	fall: 3,
	check_timeout: Duration::from_secs(3),
	connect_timeout: Duration::from_secs(3),
	retries: 3,
	idle: Duration::from_secs(24 * 60 * 60),
	maxconn: 3000,
	maxqueue: 128,
	queue_timeout: Duration::from_secs(3),
};

/// One member as the checks have found it. A member starts down, so the proxy sends nothing until
/// a member has answered as primary `rise` times in a row.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Health {
	pub up: bool,
	/// Answers in a row against the member's state: toward up while down, toward down while up.
	pub turning: u32,
}

impl Health {
	/// After one check: `primary` is whether it answered `200` to `GET /primary`.
	pub fn observe(self, primary: bool, timings: &Timings) -> Self {
		if primary == self.up {
			return Self { up: self.up, turning: 0 };
		}
		let turning = self.turning + 1;
		let needed = if self.up { timings.fall } else { timings.rise };
		if turning >= needed { Self { up: primary, turning: 0 } } else { Self { up: self.up, turning } }
	}

	/// How long until the next check, by HAProxy's three intervals.
	pub fn next(self, timings: &Timings) -> Duration {
		match (self.up, self.turning) {
			(_, 1..) => timings.fastinter,
			(true, 0) => timings.inter,
			(false, 0) => timings.downinter,
		}
	}
}

/// Where new connections go.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "target", rename_all = "lowercase")]
pub enum Target {
	/// The one member up, by its name.
	One { member: String },
	/// No member is up: new connections are closed.
	None,
	/// More than one member is up, by their names: new connections are closed too.
	Many { members: Vec<String> },
}

impl Target {
	pub fn member(&self) -> Option<&str> {
		match self {
			Self::One { member } => Some(member),
			_ => None,
		}
	}
}

/// The target, from every member's health, by name.
pub fn decide<'a>(members: impl IntoIterator<Item = (&'a str, Health)>) -> Target {
	let mut up: Vec<String> =
		members.into_iter().filter(|(_, health)| health.up).map(|(name, _)| name.to_owned()).collect();
	up.sort();
	match up.len() {
		0 => Target::None,
		1 => Target::One { member: up.remove(0) },
		_ => Target::Many { members: up },
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	fn after(answers: &[bool]) -> Health {
		answers.iter().fold(Health::default(), |health, &primary| health.observe(primary, &PIGSTY))
	}

	#[test]
	fn a_member_rises_and_falls_by_a_run_never_by_one_answer() {
		assert!(!after(&[true, true]).up);
		assert!(after(&[true, true, true]).up);
		// One failure inside a run starts it again.
		assert!(!after(&[true, true, false, true, true]).up);
		let up = after(&[true, true, true]);
		assert!(after(&[true, true, true, false, false]).up);
		assert!(!after(&[true, true, true, false, false, false]).up);
		assert_eq!(up.observe(false, &PIGSTY).observe(true, &PIGSTY), up);
	}

	#[test]
	fn a_member_turning_is_checked_fast_and_a_steady_one_at_its_own_pace() {
		let down = Health::default();
		assert_eq!(down.next(&PIGSTY), PIGSTY.downinter);
		assert_eq!(down.observe(true, &PIGSTY).next(&PIGSTY), PIGSTY.fastinter);
		let up = after(&[true, true, true]);
		assert_eq!(up.next(&PIGSTY), PIGSTY.inter);
		assert_eq!(up.observe(false, &PIGSTY).next(&PIGSTY), PIGSTY.fastinter);
	}

	#[test]
	fn exactly_one_member_up_is_the_target_and_none_or_two_is_nowhere() {
		let up = Health { up: true, turning: 0 };
		let down = Health::default();
		assert_eq!(decide([("tyo", up), ("rdu", down)]), Target::One { member: "tyo".into() });
		assert_eq!(decide([("tyo", down), ("rdu", down)]), Target::None);
		assert_eq!(
			decide([("tyo", up), ("rdu", up), ("buf", down)]),
			Target::Many { members: vec!["rdu".into(), "tyo".into()] }
		);
		assert_eq!(decide([("tyo", up)]).member(), Some("tyo"));
		assert_eq!(Target::None.member(), None);
		let written = serde_json::to_value(Target::One { member: "tyo".into() }).unwrap();
		assert_eq!(written, serde_json::json!({ "target": "one", "member": "tyo" }));
	}
}
