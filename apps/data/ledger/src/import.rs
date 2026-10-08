//! `ledger import <ledger.db>`: the SQLite the ledger kept before it moved into the cluster, copied
//! into Postgres once. Read a page at a time and written as kept -- each task's own `updated_at`,
//! no rule asked -- with what Postgres already holds left alone, so running it twice is harmless.
//! Every schema the SQLite ever had is read: the stored JSON is the record in all of them.

use crate::store::{
	EventColumns, IMPORT_EVENTS, IMPORT_TASKS, Store, StoredTask, TaskColumns, task_row,
};
use jiff::Timestamp;
use ledger::{Event, Level};
use rusqlite::{Connection, OpenFlags, OptionalExtension, params};
use serde::Serialize;
use std::path::Path;

/// Rows read and written at once: one statement, and so one round trip, a page.
const PAGE: i64 = 500;

#[derive(Debug, Default, PartialEq, Eq, Serialize)]
pub struct Imported {
	pub tasks_read: u64,
	pub tasks_written: u64,
	pub events_read: u64,
	pub events_written: u64,
}

/// One page of tasks after `after`, in key order.
pub fn tasks_after(
	sqlite: &Connection,
	after: Option<&(String, String)>,
) -> anyhow::Result<Vec<(String, String, StoredTask)>> {
	let (service, id) = after.cloned().unwrap_or_default();
	let mut select = sqlite.prepare(
		"SELECT service, id, record FROM tasks WHERE ?1 = 0 OR (service, id) > (?2, ?3)
		ORDER BY service, id LIMIT ?4",
	)?;
	let rows = select.query_map(params![after.is_some(), service, id, PAGE], |row| {
		Ok((row.get::<_, String>(0)?, row.get::<_, String>(1)?, row.get::<_, String>(2)?))
	})?;
	let mut page = Vec::new();
	for row in rows {
		let (service, id, record) = row?;
		page.push((service, id, serde_json::from_str(&record)?));
	}
	Ok(page)
}

/// One page of events after `after`, in key order; none from a schema older than events.
pub fn events_after(
	sqlite: &Connection,
	after: Option<&(String, String, i64)>,
) -> anyhow::Result<Vec<Event>> {
	let exists: Option<i64> = sqlite
		.query_row("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'events'", [], |row| {
			row.get(0)
		})
		.optional()?;
	if exists.is_none() {
		return Ok(Vec::new());
	}
	let (service, task, seq) = after.cloned().unwrap_or_default();
	let mut select = sqlite.prepare(
		"SELECT service, task, seq, at, stage, level, message, data FROM events
		WHERE ?1 = 0 OR (service, task, seq) > (?2, ?3, ?4) ORDER BY service, task, seq LIMIT ?5",
	)?;
	let rows = select.query_map(params![after.is_some(), service, task, seq, PAGE], |row| {
		Ok((
			row.get::<_, String>(0)?,
			row.get::<_, String>(1)?,
			row.get::<_, i64>(2)?,
			row.get::<_, i64>(3)?,
			row.get::<_, String>(4)?,
			row.get::<_, String>(5)?,
			row.get::<_, String>(6)?,
			row.get::<_, String>(7)?,
		))
	})?;
	let mut page = Vec::new();
	for row in rows {
		let (service, task, seq, at, stage, level, message, data) = row?;
		page.push(Event {
			service,
			task,
			seq: u64::try_from(seq)?,
			at: Timestamp::from_nanosecond(i128::from(at))?,
			stage,
			level: match level.as_str() {
				"warn" => Level::Warn,
				"error" => Level::Error,
				_ => Level::Info,
			},
			message,
			data: serde_json::from_str(&data)?,
		});
	}
	Ok(page)
}

/// Every task and event of the SQLite at `path`, opened read-only, written into `store`.
pub async fn import(store: &Store, path: &Path) -> anyhow::Result<Imported> {
	let sqlite = Connection::open_with_flags(path, OpenFlags::SQLITE_OPEN_READ_ONLY)?;
	let client = store.client().await?;
	let mut imported = Imported::default();

	let statement = client.prepare_cached(&IMPORT_TASKS).await?;
	let mut after = None;
	loop {
		let page = tasks_after(&sqlite, after.as_ref())?;
		let Some((service, id, _)) = page.last() else { break };
		after = Some((service.clone(), id.clone()));
		let mut columns = TaskColumns::default();
		for (_, _, stored) in &page {
			columns.push(task_row(stored)?);
		}
		imported.tasks_written += client.execute(&statement, &columns.params()).await?;
		imported.tasks_read += page.len() as u64;
	}

	let statement = client.prepare_cached(&IMPORT_EVENTS).await?;
	let mut after = None;
	loop {
		let page = events_after(&sqlite, after.as_ref())?;
		let Some(last) = page.last() else { break };
		after = Some((last.service.clone(), last.task.clone(), i64::try_from(last.seq)?));
		let mut columns = EventColumns::default();
		for event in &page {
			columns.push(event)?;
		}
		imported.events_written += client.execute(&statement, &columns.params()).await?;
		imported.events_read += page.len() as u64;
	}
	Ok(imported)
}

#[cfg(test)]
mod tests {
	use super::*;
	use crate::store::testing::store;

	fn nanos(at: &str) -> i64 {
		i64::try_from(at.parse::<Timestamp>().unwrap().as_nanosecond()).unwrap()
	}

	/// The flat JSON an older `Stored` or `StoredTask` wrote: `Record`'s fields and `updated_at`
	/// at the top level, and `parent` beside them from the schema that had it.
	fn old_record(id: &str, state: &str, asked_at: &str, parent: Option<(&str, &str)>) -> String {
		let mut value = serde_json::json!({
			"service": "shot", "id": id, "kind": "capture", "state": state, "caller": "public",
			"asked_at": asked_at, "summary": {}, "updated_at": asked_at,
		});
		if let Some((service, task)) = parent {
			value["parent"] = serde_json::json!({ "service": service, "id": task });
		}
		value.to_string()
	}

	/// The ledger's first schema, from 5c055b24e8d9: tasks alone, no events, a bare `Record`.
	fn first_schema(path: &Path) {
		let sqlite = Connection::open(path).unwrap();
		sqlite
			.execute_batch(
				"CREATE TABLE tasks (service TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
					state TEXT NOT NULL, caller TEXT NOT NULL, updated_at INTEGER NOT NULL,
					finished_at INTEGER, record TEXT NOT NULL, PRIMARY KEY (service, id)) WITHOUT ROWID;",
			)
			.unwrap();
		for (id, state) in [("a", "done"), ("b", "failed")] {
			let at = "2026-09-20T08:00:00Z";
			sqlite
				.execute(
					"INSERT INTO tasks VALUES ('shot', ?1, 'capture', ?2, 'public', ?3, NULL, ?4)",
					params![id, state, nanos(at), old_record(id, state, at, None)],
				)
				.unwrap();
		}
	}

	/// The schema as the ledger last wrote it, with parents, `asked_at` and events: more than a page
	/// of each, so the paging is walked.
	fn last_schema(path: &Path) {
		last_schema_holding(path, PAGE + 7, PAGE + 3);
	}

	fn last_schema_holding(path: &Path, tasks: i64, events: i64) {
		let sqlite = Connection::open(path).unwrap();
		sqlite
			.execute_batch(
				"CREATE TABLE tasks (service TEXT NOT NULL, id TEXT NOT NULL, kind TEXT NOT NULL,
					state TEXT NOT NULL, caller TEXT NOT NULL, updated_at INTEGER NOT NULL,
					finished_at INTEGER, asked_at INTEGER, parent_service TEXT, parent_id TEXT,
					record TEXT NOT NULL, PRIMARY KEY (service, id)) WITHOUT ROWID;
				CREATE TABLE events (service TEXT NOT NULL, task TEXT NOT NULL, seq INTEGER NOT NULL,
					at INTEGER NOT NULL, stage TEXT NOT NULL, level TEXT NOT NULL, message TEXT NOT NULL,
					data TEXT NOT NULL, PRIMARY KEY (service, task, seq)) WITHOUT ROWID;",
			)
			.unwrap();
		let at = "2026-10-01T09:30:00.123456789Z";
		for n in 0..tasks {
			let id = format!("t{n:04}");
			let parent = (n > 0).then_some(("shot", "t0000"));
			sqlite
				.execute(
					"INSERT INTO tasks VALUES ('shot', ?1, 'capture', 'done', 'public', ?2, ?2, ?2,
						?3, ?4, ?5)",
					params![
						id,
						nanos(at),
						parent.map(|p| p.0),
						parent.map(|p| p.1),
						old_record(&id, "done", at, parent)
					],
				)
				.unwrap();
		}
		for seq in 0..events {
			sqlite
				.execute(
					"INSERT INTO events VALUES ('shot', 't0000', ?1, ?2, 'storing', 'warn', 'slow', ?3)",
					params![1_790_000_000_000_000_000_i64 + seq, nanos(at), r#"{"ms":12}"#],
				)
				.unwrap();
		}
	}

	#[test]
	fn reads_every_schema_a_page_at_a_time() {
		let directory = tempfile::tempdir().unwrap();
		let first = directory.path().join("first.db");
		first_schema(&first);
		let sqlite = Connection::open(&first).unwrap();
		let tasks = tasks_after(&sqlite, None).unwrap();
		assert_eq!(tasks.len(), 2);
		assert!(tasks[0].2.task.parent.is_none());
		assert!(events_after(&sqlite, None).unwrap().is_empty());

		let last = directory.path().join("last.db");
		last_schema(&last);
		let sqlite = Connection::open(&last).unwrap();
		let page = tasks_after(&sqlite, None).unwrap();
		assert_eq!(page.len(), PAGE as usize);
		let after = (page[page.len() - 1].0.clone(), page[page.len() - 1].1.clone());
		assert_eq!(tasks_after(&sqlite, Some(&after)).unwrap().len(), 7);
		assert_eq!(page[1].2.task.parent.as_ref().unwrap().id, "t0000");
		// Nanoseconds survive, which the cursor of every page after it relies on.
		assert_eq!(page[0].2.updated_at.to_string(), "2026-10-01T09:30:00.123456789Z");
		let events = events_after(&sqlite, None).unwrap();
		assert_eq!(events.len(), PAGE as usize);
		assert_eq!((events[0].level, events[0].data["ms"].as_i64()), (Level::Warn, Some(12)));
	}

	#[tokio::test(flavor = "multi_thread")]
	async fn an_import_crosses_an_ocean_a_page_at_a_time() {
		let Some(store) =
			crate::store::testing::store_behind(std::time::Duration::from_millis(25)).await
		else {
			return;
		};
		let directory = tempfile::tempdir().unwrap();
		let path = directory.path().join("ledger.db");
		last_schema_holding(&path, 3000, 3000);
		let started = std::time::Instant::now();
		let imported = import(&store, &path).await.unwrap();
		let took = started.elapsed();
		eprintln!("6000 rows over 50 ms round trips took {took:?}");
		assert_eq!((imported.tasks_written, imported.events_written), (3000, 3000));
		// 50 ms a round trip: a row each would be 6000 of them, five minutes; a page each is twelve.
		assert!(took < std::time::Duration::from_secs(5), "{took:?}");
	}

	#[tokio::test]
	async fn imports_every_schema_once_however_often_it_is_run() {
		let Some(store) = store().await else { return };
		let directory = tempfile::tempdir().unwrap();
		let (first, last) = (directory.path().join("first.db"), directory.path().join("last.db"));
		first_schema(&first);
		last_schema(&last);

		let imported = import(&store, &last).await.unwrap();
		let expected = Imported {
			tasks_read: (PAGE + 7) as u64,
			tasks_written: (PAGE + 7) as u64,
			events_read: (PAGE + 3) as u64,
			events_written: (PAGE + 3) as u64,
		};
		assert_eq!(imported, expected);
		let again = import(&store, &last).await.unwrap();
		assert_eq!((again.tasks_written, again.events_written), (0, 0));
		assert_eq!(import(&store, &first).await.unwrap().tasks_written, 2);

		// Kept as it was, `updated_at` to the nanosecond, and read back as the console reads it.
		let view = store.view("shot", "t0000").await.unwrap().unwrap();
		assert_eq!(view.task.updated_at.to_string(), "2026-10-01T09:30:00.123456789Z");
		assert_eq!(view.events.len(), (PAGE + 3) as usize);
		assert_eq!(view.children.len(), 100);
		assert_eq!(store.get("shot", "b").await.unwrap().unwrap().task.record.id, "b");
	}
}
