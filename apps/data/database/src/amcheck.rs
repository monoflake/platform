//! The daily check that every btree index agrees with itself, run on every node: a standby's check
//! is the point, since `buf` replays the primary's pages by emulation. See
//! spec/architecture/databases.md, "Where it runs, and which one writes".

use crate::config::Role;
use serde::{Deserialize, Serialize};

/// Every database a connection is let into, templates aside.
pub const DATABASES: &str =
	"SELECT datname FROM pg_database WHERE datallowconn AND NOT datistemplate ORDER BY datname";
/// On the primary alone: a standby is read-only, and the extension reaches it by replication.
pub const INSTALL: &str =
	"SET client_min_messages = warning; CREATE EXTENSION IF NOT EXISTS amcheck";
pub const INSTALLED: &str = "SELECT EXISTS (SELECT FROM pg_extension WHERE extname = 'amcheck')";

/// How long one database's check may take, its every index included. A few gigabytes of index
/// read at an emulated node's pace fit in it.
pub const STATEMENT_TIMEOUT: &str = "15min";
/// How long one index waits for its lock before it is passed over, so the check never queues
/// behind a migration or a replayed exclusive lock and holds others up behind it.
pub const LOCK_TIMEOUT: &str = "5s";

/// One database's check, a round trip: every valid btree index of its own given to
/// `bt_index_check`, which takes the share lock a hot standby allows, and what each answered left
/// as JSON in a setting of the session, which the last line reads back. The indexes are listed
/// first, so no snapshot is held through the loop; a lock not had in time, or a query cancelled
/// for a conflict with replay, passes the index over rather than failing it. An error that ends it
/// is one line, the last psql writes, which the keeper carries.
pub fn script() -> String {
	format!(
		"\\set VERBOSITY terse\n\
		 \\set SHOW_CONTEXT never\n\
		 SET client_min_messages = warning;\n\
		 SET statement_timeout = '{STATEMENT_TIMEOUT}';\n\
		 SET lock_timeout = '{LOCK_TIMEOUT}';\n\
		 DO $$\n\
		 DECLARE\n\
		 \tindexes regclass[];\n\
		 \ttarget regclass;\n\
		 \tchecked integer := 0;\n\
		 \tfailed jsonb := '[]';\n\
		 \tskipped jsonb := '[]';\n\
		 BEGIN\n\
		 \tSELECT coalesce(array_agg(c.oid::regclass ORDER BY c.oid), '{{}}') INTO indexes\n\
		 \t\tFROM pg_index i\n\
		 \t\tJOIN pg_class c ON c.oid = i.indexrelid\n\
		 \t\tJOIN pg_am a ON a.oid = c.relam\n\
		 \t\tWHERE a.amname = 'btree' AND c.relkind = 'i' AND c.relpersistence <> 't'\n\
		 \t\t\tAND i.indisvalid AND i.indisready;\n\
		 \tFOREACH target IN ARRAY indexes LOOP\n\
		 \t\tBEGIN\n\
		 \t\t\tPERFORM bt_index_check(target);\n\
		 \t\t\tchecked := checked + 1;\n\
		 \t\tEXCEPTION\n\
		 \t\t\tWHEN lock_not_available OR serialization_failure THEN\n\
		 \t\t\t\tskipped := skipped || jsonb_build_object('index', target::text, 'reason', SQLERRM);\n\
		 \t\t\tWHEN OTHERS THEN\n\
		 \t\t\t\tfailed := failed || jsonb_build_object('index', target::text, 'reason', SQLERRM);\n\
		 \t\tEND;\n\
		 \tEND LOOP;\n\
		 \tPERFORM set_config('keeper.amcheck', jsonb_build_object(\n\
		 \t\t'checked', checked, 'failed', failed, 'skipped', skipped)::text, false);\n\
		 END $$;\n\
		 SELECT current_setting('keeper.amcheck');\n"
	)
}

/// An index and what it answered.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Finding {
	pub index: String,
	pub reason: String,
}

/// What `script` reads back.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
pub struct Checked {
	pub checked: u32,
	pub failed: Vec<Finding>,
	pub skipped: Vec<Finding>,
}

pub fn parse(stdout: &str) -> Result<Checked, serde_json::Error> {
	serde_json::from_str(stdout.trim())
}

/// One database, as the job reports it.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize)]
pub struct Database {
	pub name: String,
	pub checked: u32,
	#[serde(skip_serializing_if = "Vec::is_empty")]
	pub failed: Vec<Finding>,
	#[serde(skip_serializing_if = "Vec::is_empty")]
	pub skipped: Vec<Finding>,
	/// Why it was passed over whole, which fails nothing: a standby that has not yet replayed the
	/// primary installing amcheck in it.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub passed_over: Option<String>,
	/// Why its check did not finish, which fails the job: its time ran out, or Postgres refused.
	#[serde(skip_serializing_if = "Option::is_none")]
	pub unfinished: Option<String>,
}

impl Database {
	pub fn new(name: &str) -> Self {
		Self { name: name.to_owned(), ..Self::default() }
	}

	pub fn record(&mut self, checked: Checked) {
		self.checked = checked.checked;
		self.failed = checked.failed;
		self.skipped = checked.skipped;
	}
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Report {
	pub role: Role,
	pub databases: Vec<Database>,
}

impl Report {
	/// Every index that failed and every database not checked to the end, in a line, or nothing
	/// when the job passed.
	pub fn failure(&self) -> Option<String> {
		let mut found = Vec::new();
		for database in &self.databases {
			for finding in &database.failed {
				found.push(format!("{}: {}: {}", database.name, finding.index, finding.reason));
			}
			if let Some(why) = &database.unfinished {
				found.push(format!("{}: not checked to the end: {why}", database.name));
			}
		}
		if found.is_empty() {
			None
		} else {
			Some(format!("amcheck found {} problems: {}", found.len(), found.join("; ")))
		}
	}
}

#[cfg(test)]
mod tests {
	use super::*;

	#[test]
	fn checks_each_index_alone_and_lightly() {
		let script = script();
		// A standby takes the share lock bt_index_check asks for, never parent check's.
		assert!(script.contains("PERFORM bt_index_check(target);"));
		assert!(!script.contains("parent"));
		assert!(script.contains("SET statement_timeout = '15min';"));
		assert!(script.contains("SET lock_timeout = '5s';"));
		// Only a format! brace pair left for SQL's empty array, none for Rust's.
		assert!(script.contains("'{}'") && !script.contains("{{"));
		assert!(script.trim_end().ends_with("SELECT current_setting('keeper.amcheck');"));
	}

	#[test]
	fn reads_what_the_script_leaves() {
		let out = r#"{"failed": [{"index": "items_pkey", "reason": "item order invariant violated for index \"items_pkey\""}], "checked": 211, "skipped": [{"index": "jobs_due", "reason": "canceling statement due to lock timeout"}]}
"#;
		let checked = parse(out).unwrap();
		assert_eq!(checked.checked, 211);
		assert_eq!(checked.failed[0].index, "items_pkey");
		assert_eq!(checked.skipped[0].reason, "canceling statement due to lock timeout");
		assert!(parse("").is_err());
	}

	#[test]
	fn fails_on_a_broken_index_or_an_unfinished_check_and_nothing_else() {
		let mut ledger = Database::new("ledger");
		ledger.record(Checked {
			checked: 40,
			failed: vec![Finding { index: "items_pkey".into(), reason: "corrupt".into() }],
			skipped: vec![],
		});
		let mut postgres = Database::new("postgres");
		postgres.unfinished = Some("canceling statement due to statement timeout".into());
		let mut fresh = Database::new("fresh");
		fresh.passed_over = Some("amcheck is not installed in it yet".into());
		fresh.skipped = vec![Finding { index: "a".into(), reason: "lock timeout".into() }];

		let passed = Report { role: Role::Standby, databases: vec![fresh.clone()] };
		assert_eq!(passed.failure(), None);
		let written = serde_json::to_value(&passed).unwrap();
		assert_eq!(written["role"], "standby");
		assert!(written["databases"][0].get("failed").is_none());

		let failed = Report { role: Role::Primary, databases: vec![ledger, postgres, fresh] };
		let message = failed.failure().unwrap();
		assert!(message.starts_with("amcheck found 2 problems: ledger: items_pkey: corrupt; "));
		assert!(
			message.ends_with(
				"postgres: not checked to the end: canceling statement due to statement timeout"
			)
		);
	}
}
