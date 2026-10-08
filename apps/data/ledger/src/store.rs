//! The tables kept for good: tasks keyed by `service` and `id`, and their events keyed by
//! `service`, `task` and `seq`. See spec/architecture/ledger.md, "Kept for good" and "A task, and
//! the events that make it up".

use crate::migrations;
use deadpool_postgres::{GenericClient, Manager, ManagerConfig, Pool, RecyclingMethod};
use jiff::Timestamp;
use ledger::{Caller, Event, Item, Level, Record, State, Task};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::LazyLock;
use tokio_postgres::NoTls;
use tokio_postgres::types::ToSql;

/// A page's boundary: the `updated_at` and `id` of the last row already seen, so the next page
/// starts strictly after it in the newest-first order. Encoded as `<nanoseconds>:<id>` -- the
/// nanosecond count is always ASCII digits (and a leading `-` before 1970, which does not occur
/// here), so splitting on the first `:` recovers `id` whole even if `id` itself holds one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cursor {
	pub updated_at: i64,
	pub id: String,
}

impl Cursor {
	pub fn encode(&self) -> String {
		format!("{}:{}", self.updated_at, self.id)
	}

	pub fn parse(text: &str) -> Option<Self> {
		let (nanos, id) = text.split_once(':')?;
		Some(Self { updated_at: nanos.parse().ok()?, id: id.to_owned() })
	}
}

/// A task as the ledger stores and answers it: the whole task, `parent` included, plus when the
/// ledger last took it. What `libs/ledger`'s `Stored` would be, had it wrapped `Task`
/// rather than `Record`; kept here rather than there since it is this crate's wire shape alone. See
/// spec/architecture/ledger.md, "Read by the console".
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StoredTask {
	#[serde(flatten)]
	pub task: Task,
	pub updated_at: Timestamp,
}

/// One task with its events in `seq` order and the tasks it is the parent of, newest first. What
/// `GET /tasks/{service}/{id}` answers.
#[derive(Debug, Clone, Serialize)]
pub struct TaskView {
	#[serde(flatten)]
	pub task: StoredTask,
	pub events: Vec<Event>,
	pub children: Vec<StoredTask>,
}

/// How many of a task's children `GET /tasks/{service}/{id}` answers with at most. See
/// spec/architecture/ledger.md, "Read by the console".
const CHILDREN: usize = 100;

/// What `GET /tasks` narrows by, each optional and matched exactly against the column's own word
/// -- `state` and `caller` take the same lowercase spelling `serde` gives the wire, so a value that
/// is not one of them matches nothing rather than failing the request. `parent` is `service:id`,
/// split by the caller before it reaches here.
#[derive(Debug, Clone, Default)]
pub struct Filter {
	pub service: Option<String>,
	pub state: Option<String>,
	pub kind: Option<String>,
	pub caller: Option<String>,
	pub parent_service: Option<String>,
	pub parent_id: Option<String>,
}

/// A nanosecond-wide bucket the way `asked_at` truncates to the hour: dividing a nanosecond count
/// by this and back rounds down to the hour it falls in, per spec/architecture/ledger.md,
/// "Counted for telemetry".
const NANOS_PER_HOUR: i64 = 3_600_000_000_000;

/// One row of `GET /counts`: how many of `service`'s tasks asked in `hour`'s bucket hold `state`.
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct Count {
	pub service: String,
	pub hour: Timestamp,
	pub state: String,
	pub count: i64,
}

/// How many connections one ledger holds at most: writes are batched, and reads are the console's.
const CONNECTIONS: usize = 4;

pub struct Store {
	config: tokio_postgres::Config,
	pool: Pool,
}

/// A state or a caller as the column holds it: the same lowercase word `serde` gives the wire.
pub(crate) fn state_word(state: State) -> &'static str {
	match state {
		State::Queued => "queued",
		State::Running => "running",
		State::Done => "done",
		State::Failed => "failed",
	}
}

pub(crate) fn caller_word(caller: Caller) -> &'static str {
	match caller {
		Caller::Public => "public",
		Caller::Ours => "ours",
	}
}

pub(crate) fn level_word(level: Level) -> &'static str {
	match level {
		Level::Info => "info",
		Level::Warn => "warn",
		Level::Error => "error",
	}
}

fn level_of(word: &str) -> Level {
	match word {
		"warn" => Level::Warn,
		"error" => Level::Error,
		_ => Level::Info,
	}
}

pub(crate) fn nanos(at: Timestamp) -> i64 {
	i64::try_from(at.as_nanosecond()).unwrap_or(i64::MAX)
}

/// A task's columns, in the order every statement below writes them.
const COLUMNS: &str = "(service, id, kind, state, caller, updated_at, finished_at, asked_at, \
	parent_service, parent_id, record)";

/// Many tasks' columns as arrays, a row each, in `COLUMNS`' order: a page or a batch is then one
/// statement, and so one round trip to a primary an ocean away.
const TASK_ARRAYS: &str = "SELECT * FROM unnest($1::text[], $2::text[], $3::text[], $4::text[], \
	$5::text[], $6::bigint[], $7::bigint[], $8::bigint[], $9::text[], $10::text[], $11::jsonb[])";

/// The upsert rule spec/architecture/ledger.md states, as the update's own condition so two ledgers
/// writing one task at once still keep the one the rule picks: a later `asked_at` is the same task
/// asked again and always replaces what is kept; within one asking, a `finished_at` older than the
/// one kept does not, and a task with none never replaces one that has it. `replaces` is the same.
const RULE: &str = "ON CONFLICT (service, id) DO UPDATE SET
		kind = excluded.kind, state = excluded.state, caller = excluded.caller,
		updated_at = excluded.updated_at, finished_at = excluded.finished_at,
		asked_at = excluded.asked_at,
		parent_service = excluded.parent_service, parent_id = excluded.parent_id,
		record = excluded.record
	WHERE excluded.asked_at > tasks.asked_at
		OR (excluded.asked_at = tasks.asked_at AND (tasks.finished_at IS NULL
			OR (excluded.finished_at IS NOT NULL AND excluded.finished_at >= tasks.finished_at)))";

static UPSERT: LazyLock<String> = LazyLock::new(|| {
	format!(
		"INSERT INTO tasks {COLUMNS} VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) {RULE} \
		 RETURNING record"
	)
});

/// Many events, each kept once by `(service, task, seq)` and a duplicate ignored, per "Pushed to,
/// never asking"; its arrays start at `$1 + from`.
fn events_into(from: usize) -> String {
	let at = |n: usize| n + from;
	format!(
		"INSERT INTO events (service, task, seq, at, stage, level, message, data) SELECT * FROM \
		 unnest(${}::text[], ${}::text[], ${}::bigint[], ${}::bigint[], ${}::text[], ${}::text[], \
		 ${}::text[], ${}::jsonb[]) ON CONFLICT DO NOTHING",
		at(1),
		at(2),
		at(3),
		at(4),
		at(5),
		at(6),
		at(7),
		at(8)
	)
}

/// A batch as one statement: its tasks upserted by the rule, one per task, and its events kept.
static BATCH: LazyLock<String> = LazyLock::new(|| {
	format!(
		"WITH upserted AS (INSERT INTO tasks {COLUMNS} {TASK_ARRAYS} {RULE} RETURNING 1), \
		 appended AS ({} RETURNING 1) \
		 SELECT (SELECT count(*) FROM upserted), (SELECT count(*) FROM appended)",
		events_into(11)
	)
});

/// A page of the old SQLite, written as kept, what Postgres holds already left alone.
pub(crate) static IMPORT_TASKS: LazyLock<String> =
	LazyLock::new(|| format!("INSERT INTO tasks {COLUMNS} {TASK_ARRAYS} ON CONFLICT DO NOTHING"));
pub(crate) static IMPORT_EVENTS: LazyLock<String> = LazyLock::new(|| events_into(0));

impl Store {
	/// A pool over `url`, `DATABASE_URL` as `mise run database grant` writes it; nothing is connected
	/// until something is asked. `schema`, in tests alone, is where every table is made and read.
	pub fn connect(url: &str, schema: Option<&str>) -> anyhow::Result<Self> {
		Self::with(url.parse()?, schema)
	}

	fn with(mut config: tokio_postgres::Config, schema: Option<&str>) -> anyhow::Result<Self> {
		if let Some(schema) = schema {
			config.options(format!("-c search_path={schema}"));
		}
		let manager = Manager::from_config(
			config.clone(),
			NoTls,
			ManagerConfig { recycling_method: RecyclingMethod::Fast },
		);
		let pool = Pool::builder(manager).max_size(CONNECTIONS).build()?;
		Ok(Self { config, pool })
	}

	/// The schema brought up to date, on a connection of its own. See migrations.rs.
	pub async fn migrate(&self) -> anyhow::Result<Vec<i32>> {
		let (mut client, connection) = self.config.connect(NoTls).await?;
		let driven = tokio::spawn(connection);
		let applied = migrations::run(&mut client).await;
		drop(client);
		let _ = driven.await;
		Ok(applied?)
	}

	/// Whether the database answers, for `/health`.
	pub async fn answers(&self) -> anyhow::Result<()> {
		self.pool.get().await?.execute("SELECT 1", &[]).await?;
		Ok(())
	}

	/// Upserts `task`, stamping `updated_at` as now, and answers the row kept -- the new task, or
	/// the one already there when `task` loses the rule.
	pub async fn upsert(&self, task: Task) -> anyhow::Result<StoredTask> {
		let client = self.pool.get().await?;
		upsert_in(&client, task).await
	}

	pub async fn get(&self, service: &str, id: &str) -> anyhow::Result<Option<StoredTask>> {
		get_in(&self.pool.get().await?, service, id).await
	}

	/// The task, its events in `seq` order, and the tasks it is the parent of, newest first and
	/// capped at `CHILDREN`. `None` when there is no such task.
	pub async fn view(&self, service: &str, id: &str) -> anyhow::Result<Option<TaskView>> {
		let client = self.pool.get().await?;
		let Some(task) = get_in(&client, service, id).await? else { return Ok(None) };
		let rows = client
			.query(
				"SELECT seq, at, stage, level, message, data FROM events
				WHERE service = $1 AND task = $2 ORDER BY seq ASC",
				&[&service, &id],
			)
			.await?;
		let mut events = Vec::new();
		for row in rows {
			let seq: i64 = row.get(0);
			let at: i64 = row.get(1);
			events.push(Event {
				service: service.to_owned(),
				task: id.to_owned(),
				seq: u64::try_from(seq)?,
				at: Timestamp::from_nanosecond(i128::from(at))?,
				stage: row.get(2),
				level: level_of(row.get(3)),
				message: row.get(4),
				data: row.get(5),
			});
		}
		drop(client);
		let children = self
			.list(
				&Filter {
					parent_service: Some(service.to_owned()),
					parent_id: Some(id.to_owned()),
					..Filter::default()
				},
				None,
				CHILDREN,
			)
			.await?;
		Ok(Some(TaskView { task, events, children }))
	}

	/// Newest `updated_at` first, at most `limit` rows, narrowed by `filter` and, when given, only
	/// what is strictly older than `before`.
	pub async fn list(
		&self,
		filter: &Filter,
		before: Option<&Cursor>,
		limit: usize,
	) -> anyhow::Result<Vec<StoredTask>> {
		let mut clauses = Vec::new();
		let mut bound: Vec<Box<dyn ToSql + Sync + Send>> = Vec::new();
		let bind = |bound: &mut Vec<Box<dyn ToSql + Sync + Send>>,
		            value: Box<dyn ToSql + Sync + Send>| {
			bound.push(value);
			format!("${}", bound.len())
		};
		for (column, value) in [
			("service", &filter.service),
			("state", &filter.state),
			("kind", &filter.kind),
			("caller", &filter.caller),
		] {
			if let Some(value) = value {
				let at = bind(&mut bound, Box::new(value.clone()));
				clauses.push(format!("{column} = {at}"));
			}
		}
		if let (Some(service), Some(id)) = (&filter.parent_service, &filter.parent_id) {
			let service = bind(&mut bound, Box::new(service.clone()));
			let id = bind(&mut bound, Box::new(id.clone()));
			clauses.push(format!("(parent_service = {service} AND parent_id = {id})"));
		}
		if let Some(before) = before {
			let at = bind(&mut bound, Box::new(before.updated_at));
			let id = bind(&mut bound, Box::new(before.id.clone()));
			clauses.push(format!("(updated_at < {at} OR (updated_at = {at} AND id < {id}))"));
		}
		let mut query = "SELECT record FROM tasks".to_owned();
		if !clauses.is_empty() {
			query.push_str(" WHERE ");
			query.push_str(&clauses.join(" AND "));
		}
		let limit = bind(&mut bound, Box::new(i64::try_from(limit)?));
		query.push_str(&format!(" ORDER BY updated_at DESC, id DESC LIMIT {limit}"));

		let params: Vec<&(dyn ToSql + Sync)> =
			bound.iter().map(|value| &**value as &(dyn ToSql + Sync)).collect();
		let rows = self.pool.get().await?.query(&query, &params).await?;
		rows.into_iter().map(|row| Ok(serde_json::from_value(row.get(0))?)).collect()
	}

	/// Grouped by service, the hour bucket of `asked_at`, and state, for the last `hours` whole
	/// hours plus the one under way. Oldest hour first, then service, then state, per
	/// spec/architecture/ledger.md, "Counted for telemetry". `hours` is the caller's to clamp.
	pub async fn counts(&self, hours: u32) -> anyhow::Result<Vec<Count>> {
		let current_bucket = nanos(Timestamp::now()).div_euclid(NANOS_PER_HOUR);
		let window_start = (current_bucket - i64::from(hours)) * NANOS_PER_HOUR;
		let rows = self
			.pool
			.get()
			.await?
			.query(
				"SELECT service, asked_at / $1 AS bucket, state, count(*) FROM tasks
				WHERE asked_at >= $2
				GROUP BY bucket, service, state
				ORDER BY bucket ASC, service ASC, state ASC",
				&[&NANOS_PER_HOUR, &window_start],
			)
			.await?;
		let mut counts = Vec::new();
		for row in rows {
			let bucket: i64 = row.get(1);
			let hour = Timestamp::from_nanosecond(i128::from(bucket * NANOS_PER_HOUR))?;
			counts.push(Count { service: row.get(0), hour, state: row.get(2), count: row.get(3) });
		}
		Ok(counts)
	}

	/// Applies a batch of items as one statement, so atomically and in one round trip: its tasks go
	/// through the upsert rule -- among themselves first, as if sent in turn -- and its events are
	/// kept once by `(service, task, seq)`, a duplicate ignored. Answers how many items were taken.
	/// See spec/architecture/ledger.md, "Pushed to, never asking".
	pub async fn batch(&self, items: Vec<Item>) -> anyhow::Result<usize> {
		let taken = items.len();
		let (mut tasks, mut events) = (Vec::new(), EventColumns::default());
		for item in items {
			match item {
				Item::Task(task) => tasks.push(task),
				Item::Event(event) => events.push(&event)?,
			}
		}
		let now = Timestamp::now();
		let mut columns = TaskColumns::default();
		for task in winners(tasks) {
			columns.push(task_row(&StoredTask { task, updated_at: now })?);
		}
		let client = self.pool.get().await?;
		let statement = client.prepare_cached(&BATCH).await?;
		let params: Vec<&(dyn ToSql + Sync)> =
			columns.params().into_iter().chain(events.params()).collect();
		client.query_one(&statement, &params).await?;
		Ok(taken)
	}

	/// A pooled connection, for the import.
	pub(crate) async fn client(&self) -> anyhow::Result<deadpool_postgres::Object> {
		Ok(self.pool.get().await?)
	}
}

async fn get_in(
	client: &impl GenericClient,
	service: &str,
	id: &str,
) -> anyhow::Result<Option<StoredTask>> {
	let row = client
		.query_opt("SELECT record FROM tasks WHERE service = $1 AND id = $2", &[&service, &id])
		.await?;
	Ok(row.map(|row| serde_json::from_value(row.get(0))).transpose()?)
}

/// The columns a stored task is kept under, in `UPSERT`'s order.
pub(crate) fn task_row(stored: &StoredTask) -> anyhow::Result<TaskRow> {
	let record = &stored.task.record;
	Ok(TaskRow {
		service: record.service.clone(),
		id: record.id.clone(),
		kind: record.kind.clone(),
		state: state_word(record.state),
		caller: caller_word(record.caller),
		updated_at: nanos(stored.updated_at),
		finished_at: record.finished_at.map(nanos),
		asked_at: nanos(record.asked_at),
		parent_service: stored.task.parent.as_ref().map(|parent| parent.service.clone()),
		parent_id: stored.task.parent.as_ref().map(|parent| parent.id.clone()),
		record: serde_json::to_value(stored)?,
	})
}

pub(crate) struct TaskRow {
	service: String,
	id: String,
	kind: String,
	state: &'static str,
	caller: &'static str,
	updated_at: i64,
	finished_at: Option<i64>,
	asked_at: i64,
	parent_service: Option<String>,
	parent_id: Option<String>,
	record: serde_json::Value,
}

impl TaskRow {
	pub(crate) fn params(&self) -> [&(dyn ToSql + Sync); 11] {
		[
			&self.service,
			&self.id,
			&self.kind,
			&self.state,
			&self.caller,
			&self.updated_at,
			&self.finished_at,
			&self.asked_at,
			&self.parent_service,
			&self.parent_id,
			&self.record,
		]
	}
}

/// The upsert rule, run on any client or open transaction, so a batch shares one across the items
/// it carries.
async fn upsert_in(client: &impl GenericClient, task: Task) -> anyhow::Result<StoredTask> {
	let (service, id) = (task.record.service.clone(), task.record.id.clone());
	let stored = StoredTask { task, updated_at: Timestamp::now() };
	let row = task_row(&stored)?;
	if client.query_opt(UPSERT.as_str(), &row.params()).await?.is_some() {
		return Ok(stored);
	}
	get_in(client, &service, &id)
		.await?
		.ok_or_else(|| anyhow::anyhow!("{service}/{id} lost the upsert rule and is not kept"))
}

/// Whether `new` replaces `kept` by the rule `RULE` states, for tasks of one batch.
pub(crate) fn replaces(new: &Record, kept: &Record) -> bool {
	match new.asked_at.cmp(&kept.asked_at) {
		std::cmp::Ordering::Greater => true,
		std::cmp::Ordering::Less => false,
		std::cmp::Ordering::Equal => match (kept.finished_at, new.finished_at) {
			(None, _) => true,
			(Some(_), None) => false,
			(Some(old), Some(new)) => new >= old,
		},
	}
}

/// A batch's tasks, one per task: the one the rule keeps where a task is sent more than once, as if
/// each had been upserted in turn. One statement may not update a row twice.
pub(crate) fn winners(tasks: Vec<Task>) -> Vec<Task> {
	let mut kept: Vec<Task> = Vec::new();
	let mut at: HashMap<(String, String), usize> = HashMap::new();
	for task in tasks {
		let key = (task.record.service.clone(), task.record.id.clone());
		match at.get(&key) {
			Some(&index) => {
				if replaces(&task.record, &kept[index].record) {
					kept[index] = task;
				}
			}
			None => {
				at.insert(key, kept.len());
				kept.push(task);
			}
		}
	}
	kept
}

/// Tasks' columns as arrays, for `TASK_ARRAYS`.
#[derive(Default)]
pub(crate) struct TaskColumns {
	service: Vec<String>,
	id: Vec<String>,
	kind: Vec<String>,
	state: Vec<&'static str>,
	caller: Vec<&'static str>,
	updated_at: Vec<i64>,
	finished_at: Vec<Option<i64>>,
	asked_at: Vec<i64>,
	parent_service: Vec<Option<String>>,
	parent_id: Vec<Option<String>>,
	record: Vec<serde_json::Value>,
}

impl TaskColumns {
	pub(crate) fn push(&mut self, row: TaskRow) {
		self.service.push(row.service);
		self.id.push(row.id);
		self.kind.push(row.kind);
		self.state.push(row.state);
		self.caller.push(row.caller);
		self.updated_at.push(row.updated_at);
		self.finished_at.push(row.finished_at);
		self.asked_at.push(row.asked_at);
		self.parent_service.push(row.parent_service);
		self.parent_id.push(row.parent_id);
		self.record.push(row.record);
	}

	pub(crate) fn params(&self) -> [&(dyn ToSql + Sync); 11] {
		[
			&self.service,
			&self.id,
			&self.kind,
			&self.state,
			&self.caller,
			&self.updated_at,
			&self.finished_at,
			&self.asked_at,
			&self.parent_service,
			&self.parent_id,
			&self.record,
		]
	}
}

/// Events' columns as arrays, for `events_into`.
#[derive(Default)]
pub(crate) struct EventColumns {
	service: Vec<String>,
	task: Vec<String>,
	seq: Vec<i64>,
	at: Vec<i64>,
	stage: Vec<String>,
	level: Vec<&'static str>,
	message: Vec<String>,
	data: Vec<serde_json::Value>,
}

impl EventColumns {
	pub(crate) fn push(&mut self, event: &Event) -> anyhow::Result<()> {
		self.seq.push(i64::try_from(event.seq)?);
		self.service.push(event.service.clone());
		self.task.push(event.task.clone());
		self.at.push(nanos(event.at));
		self.stage.push(event.stage.clone());
		self.level.push(level_word(event.level));
		self.message.push(event.message.clone());
		self.data.push(event.data.clone());
		Ok(())
	}

	pub(crate) fn params(&self) -> [&(dyn ToSql + Sync); 8] {
		[
			&self.service,
			&self.task,
			&self.seq,
			&self.at,
			&self.stage,
			&self.level,
			&self.message,
			&self.data,
		]
	}
}

#[cfg(test)]
pub(crate) mod testing {
	//! The SQL is run against a Postgres only where `LEDGER_TEST_DATABASE_URL` names one, each test
	//! in a schema of its own: `mise run test-sql` starts one, and CI has its own. Without it those
	//! tests pass over themselves and say so, except in CI, where that is a failure.

	use super::Store;
	use std::sync::atomic::{AtomicU32, Ordering};
	use std::time::Duration;
	use tokio::io::{AsyncReadExt, AsyncWriteExt};
	use tokio::net::tcp::{OwnedReadHalf, OwnedWriteHalf};
	use tokio::net::{TcpListener, TcpStream};
	use tokio::sync::mpsc;
	use tokio::time::Instant;
	use tokio_postgres::config::Host;

	static NEXT: AtomicU32 = AtomicU32::new(0);

	/// A schema of its own in the test database, or None, said so, when there is no database.
	async fn schema() -> Option<(String, String)> {
		let Ok(url) = std::env::var("LEDGER_TEST_DATABASE_URL") else {
			let ci = std::env::var("CI").is_ok_and(|value| !value.is_empty());
			assert!(!ci, "CI is set and LEDGER_TEST_DATABASE_URL is not: CI runs every SQL test");
			eprintln!("LEDGER_TEST_DATABASE_URL is not set; this test's SQL is not run");
			return None;
		};
		let schema = format!(
			"test_{}_{}_{}",
			std::process::id(),
			jiff::Timestamp::now().as_millisecond(),
			NEXT.fetch_add(1, Ordering::Relaxed)
		);
		let (client, connection) = tokio_postgres::connect(&url, tokio_postgres::NoTls).await.unwrap();
		tokio::spawn(connection);
		client.batch_execute(&format!("CREATE SCHEMA {schema}")).await.unwrap();
		Some((url, schema))
	}

	pub async fn store() -> Option<Store> {
		let (url, schema) = schema().await?;
		let store = Store::connect(&url, Some(&schema)).unwrap();
		store.migrate().await.unwrap();
		Some(store)
	}

	/// A store whose every byte to and from Postgres is held `delay` each way, as a primary an
	/// ocean away holds it: what costs a round trip per row shows here.
	pub async fn store_behind(delay: Duration) -> Option<Store> {
		let (url, schema) = schema().await?;
		Store::connect(&url, Some(&schema)).unwrap().migrate().await.unwrap();
		let config: tokio_postgres::Config = url.parse().unwrap();
		let Host::Tcp(host) = &config.get_hosts()[0] else { panic!("a TCP host, please") };
		let port = proxy((host.clone(), config.get_ports()[0]), delay).await;
		let mut near = tokio_postgres::Config::new();
		near.host("127.0.0.1").port(port).user(config.get_user().unwrap());
		near.dbname(config.get_dbname().unwrap());
		if let Some(password) = config.get_password() {
			near.password(password);
		}
		Some(Store::with(near, Some(&schema)).unwrap())
	}

	async fn proxy(upstream: (String, u16), delay: Duration) -> u16 {
		let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
		let port = listener.local_addr().unwrap().port();
		tokio::spawn(async move {
			while let Ok((client, _)) = listener.accept().await {
				let upstream = upstream.clone();
				tokio::spawn(async move {
					let Ok(server) = TcpStream::connect((upstream.0.as_str(), upstream.1)).await else {
						return;
					};
					let ((client_in, client_out), (server_in, server_out)) =
						(client.into_split(), server.into_split());
					tokio::join!(late(client_in, server_out, delay), late(server_in, client_out, delay));
				});
			}
		});
		port
	}

	/// `from` copied to `to`, each piece `delay` after it arrived and none held back by another.
	async fn late(mut from: OwnedReadHalf, mut to: OwnedWriteHalf, delay: Duration) {
		let (send, mut received) = mpsc::unbounded_channel::<(Instant, Vec<u8>)>();
		let reading = async move {
			let mut buffer = vec![0; 64 * 1024];
			while let Ok(read) = from.read(&mut buffer).await {
				if read == 0 || send.send((Instant::now() + delay, buffer[..read].to_vec())).is_err() {
					break;
				}
			}
		};
		let writing = async move {
			while let Some((due, bytes)) = received.recv().await {
				tokio::time::sleep_until(due).await;
				if to.write_all(&bytes).await.is_err() {
					break;
				}
			}
			let _ = to.shutdown().await;
		};
		tokio::join!(reading, writing);
	}

	/// A store over a database that is never reached, for what is refused before the store is asked.
	pub fn unreached() -> Store {
		Store::connect("host=unreached.invalid user=nobody dbname=none", None).unwrap()
	}
}

/// Test-only: overwrites a stored task's `updated_at` directly, keeping the column and the JSON
/// in step, so a paging test can force two rows to tie at the same nanosecond.
#[cfg(test)]
impl Store {
	pub async fn force_updated_at(&self, service: &str, id: &str, at: i64) {
		let mut stored = self.get(service, id).await.unwrap().unwrap();
		stored.updated_at = Timestamp::from_nanosecond(i128::from(at)).unwrap();
		let record = serde_json::to_value(&stored).unwrap();
		self
			.pool
			.get()
			.await
			.unwrap()
			.execute(
				"UPDATE tasks SET updated_at = $1, record = $2 WHERE service = $3 AND id = $4",
				&[&at, &record, &service, &id],
			)
			.await
			.unwrap();
	}
}

#[cfg(test)]
mod tests {
	use super::testing::store;
	use super::*;
	use ledger::Record;

	fn record(id: &str, state: State, finished_at: Option<&str>) -> Record {
		Record {
			service: "shot".into(),
			id: id.into(),
			kind: "capture".into(),
			state,
			caller: Caller::Public,
			asked_at: "2026-09-28T12:00:00Z".parse().unwrap(),
			started_at: None,
			finished_at: finished_at.map(|at| at.parse().unwrap()),
			summary: serde_json::json!({}),
			detail: None,
		}
	}

	fn task(id: &str, state: State, finished_at: Option<&str>) -> Task {
		record(id, state, finished_at).into()
	}

	fn asked_at(id: &str, state: State, asked_at: &str, finished_at: Option<&str>) -> Task {
		Task {
			record: Record { asked_at: asked_at.parse().unwrap(), ..record(id, state, finished_at) },
			parent: None,
		}
	}

	fn event(task: &str, seq: u64) -> Event {
		Event {
			service: "shot".into(),
			task: task.into(),
			seq,
			at: "2026-09-28T12:00:00Z".parse().unwrap(),
			stage: "resolving".into(),
			level: Level::Info,
			message: "starting".into(),
			data: serde_json::Value::Null,
		}
	}

	#[test]
	fn a_batch_keeps_one_of_each_task_as_the_rule_would_in_turn() {
		let done = task("a", State::Done, Some("2026-09-28T12:05:00Z"));
		let late = task("a", State::Running, Some("2026-09-28T12:04:00Z"));
		let kept = winners(vec![
			task("a", State::Queued, None),
			done.clone(),
			late,
			task("b", State::Queued, None),
		]);
		assert_eq!(kept.len(), 2);
		assert_eq!((kept[0].record.id.as_str(), kept[0].record.state), ("a", State::Done));
		assert_eq!(kept[1].record.id, "b");
		// Asked again later: replaces even a finished one.
		let again = asked_at("a", State::Queued, "2026-09-28T13:00:00Z", None);
		assert_eq!(winners(vec![done, again])[0].record.state, State::Queued);
	}

	#[tokio::test]
	async fn a_batch_sending_one_task_several_times_keeps_what_the_rule_keeps() {
		let Some(store) = store().await else { return };
		let items = vec![
			Item::Task(task("a", State::Queued, None)),
			Item::Task(task("a", State::Done, Some("2026-09-28T12:05:00Z"))),
			Item::Task(task("a", State::Running, Some("2026-09-28T12:04:00Z"))),
			Item::Event(event("a", 1)),
			Item::Event(event("a", 1)),
		];
		assert_eq!(store.batch(items).await.unwrap(), 5);
		let view = store.view("shot", "a").await.unwrap().unwrap();
		assert_eq!(view.task.task.record.state, State::Done);
		assert_eq!(view.events.len(), 1);
	}

	#[tokio::test(flavor = "multi_thread")]
	async fn a_batch_is_one_round_trip_however_many_items_it_carries() {
		let Some(store) = super::testing::store_behind(std::time::Duration::from_millis(25)).await
		else {
			return;
		};
		// The connection and its prepared statement first, as a running ledger has them.
		store.batch(vec![Item::Event(event("warm", 1))]).await.unwrap();
		let mut items = Vec::new();
		for n in 0..100 {
			let id = format!("t{n}");
			items.push(Item::Task(task(&id, State::Running, None)));
			items.push(Item::Task(task(&id, State::Done, Some("2026-09-28T12:05:00Z"))));
			items.push(Item::Event(event(&id, 1)));
		}
		let started = std::time::Instant::now();
		assert_eq!(store.batch(items).await.unwrap(), 300);
		let took = started.elapsed();
		eprintln!("a batch of 300 items over 50 ms round trips took {took:?}");
		// 50 ms a round trip: 300 of them would be 15 s.
		assert!(took < std::time::Duration::from_millis(500), "{took:?}");
		let done = Filter { state: Some("done".into()), ..Filter::default() };
		assert_eq!(store.list(&done, None, 500).await.unwrap().len(), 100);
	}

	#[test]
	fn a_cursor_round_trips_through_its_encoding() {
		let cursor = Cursor { updated_at: 12345, id: "with:colon".into() };
		assert_eq!(Cursor::parse(&cursor.encode()), Some(cursor));
	}

	#[tokio::test]
	async fn a_late_running_does_not_undo_a_done() {
		let Some(store) = store().await else { return };
		store.upsert(task("a", State::Done, Some("2026-09-28T12:05:00Z"))).await.unwrap();
		let kept = store.upsert(task("a", State::Running, Some("2026-09-28T12:04:00Z"))).await.unwrap();
		assert_eq!(kept.task.record.state, State::Done);
		assert_eq!(store.get("shot", "a").await.unwrap().unwrap().task.record.state, State::Done);
	}

	#[tokio::test]
	async fn a_record_without_finished_at_never_replaces_one_that_has_it() {
		let Some(store) = store().await else { return };
		store.upsert(task("a", State::Done, Some("2026-09-28T12:05:00Z"))).await.unwrap();
		let kept = store.upsert(task("a", State::Running, None)).await.unwrap();
		assert_eq!(kept.task.record.state, State::Done);
	}

	#[tokio::test]
	async fn a_later_asked_at_always_replaces_the_kept_one() {
		let Some(store) = store().await else { return };
		let failed = asked_at("a", State::Failed, "2026-09-28T12:00:00Z", Some("2026-09-28T12:00:00Z"));
		store.upsert(failed.clone()).await.unwrap();
		let kept =
			store.upsert(asked_at("a", State::Queued, "2026-09-28T13:00:00Z", None)).await.unwrap();
		assert_eq!(kept.task.record.state, State::Queued);

		let failed = Task { record: Record { id: "b".into(), ..failed.record }, parent: None };
		store.upsert(failed).await.unwrap();
		let kept =
			store.upsert(asked_at("b", State::Queued, "2026-09-28T12:00:00Z", None)).await.unwrap();
		assert_eq!(kept.task.record.state, State::Failed);
	}

	#[tokio::test]
	async fn a_later_finished_at_replaces_the_kept_one() {
		let Some(store) = store().await else { return };
		store.upsert(task("a", State::Running, Some("2026-09-28T12:00:00Z"))).await.unwrap();
		let kept = store.upsert(task("a", State::Done, Some("2026-09-28T12:05:00Z"))).await.unwrap();
		assert_eq!(kept.task.record.state, State::Done);
	}

	#[tokio::test]
	async fn sending_the_same_record_twice_is_harmless() {
		let Some(store) = store().await else { return };
		let first = store.upsert(task("a", State::Queued, None)).await.unwrap();
		let second = store.upsert(task("a", State::Queued, None)).await.unwrap();
		assert_eq!(first.task, second.task);
	}

	#[tokio::test]
	async fn the_rule_holds_for_writes_that_race() {
		let Some(store) = store().await else { return };
		let store = std::sync::Arc::new(store);
		// Each pair races a `done` against a late `running` of the same asking, many times over.
		let mut racing = Vec::new();
		for n in 0..40 {
			let id = format!("race-{}", (n / 2) % 10);
			let (store, late) = (store.clone(), n % 2 == 0);
			racing.push(tokio::spawn(async move {
				let (state, at) = if late {
					(State::Running, "2026-09-28T12:04:00Z")
				} else {
					(State::Done, "2026-09-28T12:05:00Z")
				};
				store.upsert(task(&id, state, Some(at))).await.unwrap();
			}));
		}
		for racer in racing {
			racer.await.unwrap();
		}
		for n in 0..10 {
			let kept = store.get("shot", &format!("race-{n}")).await.unwrap().unwrap();
			assert_eq!(kept.task.record.state, State::Done, "race-{n}");
		}
	}

	#[tokio::test]
	async fn lists_newest_updated_at_first_paged_and_filtered() {
		let Some(store) = store().await else { return };
		for id in ["a", "b", "c"] {
			store.upsert(task(id, State::Done, Some("2026-09-28T12:00:00Z"))).await.unwrap();
		}
		store.upsert(task("d", State::Failed, Some("2026-09-28T12:00:00Z"))).await.unwrap();

		let all = store.list(&Filter::default(), None, 10).await.unwrap();
		assert_eq!(all.len(), 4);
		assert_eq!(all[0].task.record.id, "d");
		assert_eq!(all[3].task.record.id, "a");

		let page = store.list(&Filter::default(), None, 2).await.unwrap();
		assert_eq!(page.len(), 2);
		let cursor =
			Cursor { updated_at: nanos(page[1].updated_at), id: page[1].task.record.id.clone() };
		let rest = store.list(&Filter::default(), Some(&cursor), 10).await.unwrap();
		assert_eq!(rest.len(), 2);
		assert_eq!(rest[0].task.record.id, all[2].task.record.id);

		let failed = Filter { state: Some("failed".into()), ..Filter::default() };
		let failed = store.list(&failed, None, 10).await.unwrap();
		assert_eq!(failed.len(), 1);
		assert_eq!(failed[0].task.record.id, "d");
		let nothing = Filter { state: Some("sleeping".into()), ..Filter::default() };
		assert!(store.list(&nothing, None, 10).await.unwrap().is_empty());
	}

	#[tokio::test]
	async fn a_batch_stores_a_task_and_its_events_once_even_sent_twice() {
		let Some(store) = store().await else { return };
		let items = vec![
			Item::Task(task("a", State::Running, None)),
			Item::Event(event("a", 1)),
			Item::Event(event("a", 2)),
		];
		assert_eq!(store.batch(items.clone()).await.unwrap(), 3);
		assert_eq!(store.batch(items).await.unwrap(), 3);

		let view = store.view("shot", "a").await.unwrap().unwrap();
		assert_eq!(view.task.task.record.state, State::Running);
		assert_eq!(view.events.len(), 2);
		assert_eq!(view.events[0].seq, 1);
		assert_eq!(view.events[1].seq, 2);
	}

	#[tokio::test]
	async fn events_answer_in_seq_order_however_they_arrived() {
		let Some(store) = store().await else { return };
		store.upsert(task("a", State::Running, None)).await.unwrap();
		// The size a real seq has: a moment in nanoseconds.
		let base = 1_790_000_000_000_000_000;
		let arrived = [5, 1, 3].map(|n| Item::Event(event("a", base + n)));
		store.batch(arrived.to_vec()).await.unwrap();
		let view = store.view("shot", "a").await.unwrap().unwrap();
		let seqs: Vec<u64> = view.events.iter().map(|event| event.seq - base).collect();
		assert_eq!(seqs, vec![1, 3, 5]);
	}

	#[tokio::test]
	async fn the_task_view_carries_its_children_newest_first() {
		let Some(store) = store().await else { return };
		store.upsert(task("parent", State::Running, None)).await.unwrap();
		for id in ["child-a", "child-b"] {
			let mut child = task(id, State::Running, None);
			child.parent = Some(ledger::Parent { service: "shot".into(), id: "parent".into() });
			store.upsert(child).await.unwrap();
		}
		let view = store.view("shot", "parent").await.unwrap().unwrap();
		assert_eq!(view.children.len(), 2);
		assert_eq!(view.children[0].task.record.id, "child-b");
		assert_eq!(view.children[1].task.record.id, "child-a");
	}

	#[tokio::test]
	async fn the_upsert_rule_still_holds_through_a_batch() {
		let Some(store) = store().await else { return };
		let done = Item::Task(task("a", State::Done, Some("2026-09-28T12:05:00Z")));
		store.batch(vec![done]).await.unwrap();
		let late = Item::Task(task("a", State::Running, Some("2026-09-28T12:04:00Z")));
		store.batch(vec![late]).await.unwrap();
		assert_eq!(store.get("shot", "a").await.unwrap().unwrap().task.record.state, State::Done);
	}

	/// A task `hours_ago` hours before now, for `service` under `id` and `state`. See
	/// spec/architecture/ledger.md, "Counted for telemetry".
	fn asked_hours_ago(service: &str, id: &str, state: State, hours_ago: i64) -> Task {
		let asked_at =
			Timestamp::now().checked_sub(jiff::SignedDuration::from_hours(hours_ago)).unwrap();
		Task {
			record: Record { service: service.into(), asked_at, ..record(id, state, None) },
			parent: None,
		}
	}

	#[tokio::test]
	async fn counts_group_by_service_hour_bucket_and_state() {
		let Some(store) = store().await else { return };
		store.upsert(asked_hours_ago("shot", "a", State::Done, 0)).await.unwrap();
		store.upsert(asked_hours_ago("shot", "b", State::Done, 0)).await.unwrap();
		store.upsert(asked_hours_ago("shot", "c", State::Failed, 0)).await.unwrap();
		store.upsert(asked_hours_ago("geo", "d", State::Done, 0)).await.unwrap();

		let counts = store.counts(1).await.unwrap();
		let count = |service: &str, state: &str| {
			counts.iter().find(|row| row.service == service && row.state == state).map(|row| row.count)
		};
		assert_eq!(count("shot", "done"), Some(2));
		assert_eq!(count("shot", "failed"), Some(1));
		assert_eq!(count("geo", "done"), Some(1));
	}

	#[tokio::test]
	async fn the_window_covers_the_last_hours_plus_the_one_under_way() {
		let Some(store) = store().await else { return };
		store.upsert(asked_hours_ago("shot", "now", State::Done, 0)).await.unwrap();
		store.upsert(asked_hours_ago("shot", "one-ago", State::Done, 1)).await.unwrap();
		store.upsert(asked_hours_ago("shot", "two-ago", State::Done, 2)).await.unwrap();
		let total = |counts: Vec<Count>| counts.iter().map(|row| row.count).sum::<i64>();
		assert_eq!(total(store.counts(1).await.unwrap()), 2);
		assert_eq!(total(store.counts(2).await.unwrap()), 3);
		assert!(store.counts(24).await.unwrap().iter().all(|row| row.service == "shot"));
	}

	#[tokio::test]
	async fn migrating_again_changes_nothing() {
		let Some(store) = store().await else { return };
		assert!(store.migrate().await.unwrap().is_empty());
	}
}
