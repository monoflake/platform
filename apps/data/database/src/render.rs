//! Patroni's configuration, written afresh to the scratch directory on every start, so what runs is
//! what this file says and nothing an earlier start left behind. It is JSON, which YAML reads, so
//! every value is escaped by serde rather than by hand. See spec/architecture/databases.md, "Where
//! it runs, and which one writes". Tuned values are Pigsty v4.5.0's, each naming the file it came
//! from in that repository: `roles/pgsql/defaults/main.yml` and the `tiny.yml` template beside it
//! in `roles/pgsql/templates/`, for nodes of one to three cores.

use crate::config::Config;
use serde_json::{Value, json};
use std::path::Path;

/// Postgres's own port, published to the tailnet with Patroni's REST.
pub const PORT: u16 = 5432;
/// Patroni's REST, which every member asks the others on, and the operator's switchover too.
pub const REST: u16 = 8008;
/// etcd's client port, on each core.
pub const ETCD: u16 = 2379;
/// The role a standby copies and follows the primary as.
pub const REPLICATOR: &str = "replicator";
pub const SUPERUSER: &str = "postgres";
/// The name Patroni's REST asks for with the password, and the name Patroni gives etcd.
pub const REST_USER: &str = "patroni";
/// The cluster's name in etcd, under the namespace below.
pub const SCOPE: &str = "platform";
const NAMESPACE: &str = "/database/";
const BIN: &str = "/usr/lib/postgresql/18/bin";

/// The lease, and how often it is renewed: a primary that cannot renew it for `TTL` seconds stops
/// taking writes, which is the fence. `TTL` must be at least `LOOP_WAIT` and twice `RETRY`.
/// Pigsty's `norm` plan, `pg_rto_plan` in defaults/main.yml: ttl, loop, retry and start.
pub const TTL: u64 = 30;
pub const LOOP_WAIT: u64 = 5;
const RETRY: u64 = 10;
/// How long a primary that crashed may take to come back before another is promoted.
const PRIMARY_START_TIMEOUT: u64 = 25;
/// A standby more than this behind is never promoted: Pigsty's `pg_rpo`, defaults/main.yml.
const MAXIMUM_LAG: u64 = 1024 * 1024;
/// Not Pigsty's 250 for its tiny template, which counts on PgBouncer in front: every app's own pool
/// connects straight to the cluster. The same on every member, as a standby must have at least the
/// primary's.
pub const MAX_CONNECTIONS: u64 = 50;

/// tiny.yml scales these by the disk up to 200, 200 and 2000 GB; a shared /data holds them lower.
const MIN_WAL_GB: u64 = 2;
const MAX_WAL_GB: u64 = 8;
const TEMP_FILES_GB: u64 = 20;

/// What this member's container has, which its own share of the tuning is sized from.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Machine {
	pub memory_mb: u64,
	pub cpus: u64,
	pub disk_bytes: u64,
}

impl Machine {
	/// The container's memory ceiling, or half the machine's where that is less, since every node
	/// runs host, Caddy, the relay and the rest beside it; the cores it may use; and the size of the
	/// disk `data` is on, or its parent's before it exists.
	pub fn read(data: &Path) -> Self {
		let cgroup = std::fs::read_to_string("/sys/fs/cgroup/memory.max").ok();
		let meminfo = std::fs::read_to_string("/proc/meminfo").unwrap_or_default();
		let cpus = std::thread::available_parallelism().map_or(1, |n| n.get() as u64);
		let on = if data.exists() { data } else { data.parent().unwrap_or(data) };
		Self { memory_mb: memory_mb(cgroup.as_deref(), &meminfo), cpus, disk_bytes: disk_bytes(on) }
	}
}

/// The lesser of a cgroup's `memory.max`, which says `max` for none, and half `MemTotal`, in MiB.
pub fn memory_mb(cgroup: Option<&str>, meminfo: &str) -> u64 {
	let total = meminfo
		.lines()
		.find_map(|line| line.strip_prefix("MemTotal:"))
		.and_then(|rest| rest.split_whitespace().next()?.parse::<u64>().ok())
		.map_or(u64::MAX, |kib| kib / 1024 / 2);
	let ceiling = cgroup
		.and_then(|text| text.trim().parse::<u64>().ok())
		.map_or(u64::MAX, |bytes| bytes / (1024 * 1024));
	match total.min(ceiling) {
		u64::MAX => 512,
		known => known,
	}
}

// statvfs's fields are of other widths on other platforms: a conversion a no-op on one is needed on
// another.
#[allow(clippy::useless_conversion)]
fn disk_bytes(path: &Path) -> u64 {
	use std::os::unix::ffi::OsStrExt;
	let Ok(name) = std::ffi::CString::new(path.as_os_str().as_bytes()) else { return 0 };
	let mut stat = std::mem::MaybeUninit::<libc::statvfs>::uninit();
	// SAFETY: a valid C string and a buffer the size of what statvfs writes.
	if unsafe { libc::statvfs(name.as_ptr(), stat.as_mut_ptr()) } != 0 {
		return 0;
	}
	// SAFETY: statvfs returned 0, so it filled the buffer.
	let stat = unsafe { stat.assume_init() };
	u64::from(stat.f_blocks).saturating_mul(u64::from(stat.f_frsize))
}

/// `patroni.yml` for this node: its data in `data`, its Postgres configuration written to `run`.
pub fn patroni(config: &Config, machine: Machine, data: &Path, run: &Path) -> Value {
	let address = config.address();
	let etcd: Vec<String> = config.quorum.iter().map(|member| format!("{member}:{ETCD}")).collect();
	let superuser = json!({ "username": SUPERUSER, "password": config.superuser_password });
	json!({
		"scope": SCOPE,
		"namespace": NAMESPACE,
		"name": config.node,
		"restapi": {
			"listen": format!("0.0.0.0:{REST}"),
			"connect_address": format!("{address}:{REST}"),
			"authentication": { "username": REST_USER, "password": config.patroni_password },
		},
		// etcd answers only with a password, the same as the REST's. See spec/todo/todo.md, "The
		// database".
		"etcd3": {
			"hosts": etcd,
			"protocol": "http",
			"username": REST_USER,
			"password": config.patroni_password,
		},
		"bootstrap": {
			"dcs": {
				"ttl": TTL,
				"loop_wait": LOOP_WAIT,
				"retry_timeout": RETRY,
				"primary_start_timeout": PRIMARY_START_TIMEOUT,
				"maximum_lag_on_failover": MAXIMUM_LAG,
				// Asynchronous, as decided; tiny.yml turns it on only for an RPO of nothing.
				"synchronous_mode": false,
				// A leader that reaches every member keeps leading while etcd is down; tiny.yml too.
				"failsafe_mode": true,
				"postgresql": {
					"use_pg_rewind": true,
					// No slots: a member away for long would hold WAL on the primary without end;
					// one that falls behind `wal_keep_size` catches up from the archive instead.
					"use_slots": false,
					// tiny.yml: a rewind that fails reclones; a diverged timeline is rewound first.
					"remove_data_directory_on_rewind_failure": true,
					"remove_data_directory_on_diverged_timelines": false,
					"parameters": shared(),
				},
			},
			// Data checksums are Postgres 18's default and stay, since `pg_rewind` needs them. The
			// builtin locale ties sorting to Postgres rather than to the C library of whichever
			// image restores it.
			"initdb": [
				{ "encoding": "UTF8" },
				{ "locale": "C.UTF-8" },
				{ "locale-provider": "builtin" },
				{ "builtin-locale": "C.UTF-8" },
				{ "auth-local": "peer" },
				{ "auth-host": "scram-sha-256" },
			],
		},
		"postgresql": {
			"listen": format!("0.0.0.0:{PORT}"),
			"connect_address": format!("{address}:{PORT}"),
			"data_dir": data,
			"config_dir": run.join("postgresql"),
			"bin_dir": BIN,
			"pgpass": run.join("pgpass"),
			"authentication": {
				"superuser": superuser,
				"rewind": superuser,
				"replication": { "username": REPLICATOR, "password": config.replication_password },
			},
			"parameters": local(machine, run),
			// A standby that fell behind what the primary keeps catches up from the archive.
			"recovery_conf": { "restore_command": "wal-g wal-fetch %f %p" },
			"pg_hba": pg_hba(),
			// A new member, or one whose rewind failed, from the latest base backup first and from
			// the primary second.
			"create_replica_methods": ["wal_g", "basebackup"],
			"wal_g": { "command": "/usr/local/bin/database fetch-backup", "no_leader": true },
			// Patroni streams the WAL itself and refuses to be told how; the rate is tiny.yml's.
			"basebackup": [{ "max-rate": "1000M" }, { "checkpoint": "fast" }],
		},
		// tiny.yml's clonefrom: a new member may copy a replica rather than cross to the primary.
		"tags": {
			"failover_priority": config.priority,
			"nofailover": config.priority == 0,
			"clonefrom": true,
		},
		"watchdog": { "mode": "off" },
	})
}

/// What every member must agree on, kept in etcd by Patroni: tiny.yml's, but for the connections
/// and slots this design keeps, and its logging, which goes to files a container does not keep.
fn shared() -> Value {
	json!({
		"max_connections": MAX_CONNECTIONS,
		"superuser_reserved_connections": 10,
		"track_commit_timestamp": "on",
		// Logical, for a major's upgrade by logical replication; see spec/architecture/databases.md.
		"wal_level": "logical",
		"wal_log_hints": "on",
		"wal_compression": "lz4",
		// tiny.yml's max(cores + 4, 12) + 8, the same on every member up to eight cores.
		"max_worker_processes": 20,
		"max_wal_senders": 50,
		"max_replication_slots": 50,
		"hot_standby": "on",
		"huge_pages": "try",
		"io_method": "worker",
		"io_workers": 3,
		"vacuum_cost_delay": "20ms",
		"vacuum_cost_limit": 2000,
		"bgwriter_delay": "10ms",
		"bgwriter_lru_maxpages": 800,
		"bgwriter_lru_multiplier": 5.0,
		"wal_buffers": "16MB",
		"wal_writer_delay": "20ms",
		"wal_writer_flush_after": "1MB",
		"commit_delay": 20,
		"commit_siblings": 10,
		"checkpoint_timeout": "15min",
		"checkpoint_completion_target": 0.95,
		"max_standby_archive_delay": "10min",
		"max_standby_streaming_delay": "3min",
		"wal_receiver_status_interval": "1s",
		// Also spares amcheck on a standby its conflicts with replay.
		"hot_standby_feedback": "on",
		"wal_receiver_timeout": "60s",
		"max_logical_replication_workers": 8,
		"max_sync_workers_per_subscription": 6,
		"random_page_cost": 1.1,
		"effective_io_concurrency": 200,
		"maintenance_io_concurrency": 100,
		"default_statistics_target": 200,
		"log_checkpoints": "on",
		"log_lock_waits": "on",
		"log_temp_files": 1024,
		// The keeper and `database grant` turn this off for their own sessions, whose statements
		// carry passwords.
		"log_statement": "ddl",
		"log_min_duration_statement": 100,
		"log_autovacuum_min_duration": "1s",
		"track_io_timing": "on",
		"track_functions": "all",
		"track_activity_query_size": 8192,
		"autovacuum_max_workers": 2,
		"autovacuum_naptime": "1min",
		"autovacuum_vacuum_threshold": 500,
		"autovacuum_analyze_threshold": 250,
		"autovacuum_freeze_max_age": 1_000_000_000,
		"deadlock_timeout": "50ms",
		"idle_in_transaction_session_timeout": "10min",
		"shared_preload_libraries": "pg_stat_statements, auto_explain",
		"auto_explain.log_min_duration": "1s",
		"auto_explain.log_analyze": "on",
		"auto_explain.log_verbose": "on",
		"auto_explain.log_timing": "on",
		"auto_explain.log_nested_statements": true,
		"pg_stat_statements.max": 2500,
		"pg_stat_statements.track": "all",
		"pg_stat_statements.track_utility": "off",
		"pg_stat_statements.track_planning": "off",
		// A database copied by reflink on btrfs, which every node's /data is.
		"file_copy_method": "clone",
	})
}

/// This member's own: the archive, and tiny.yml's sizes from its memory, cores and disk, so `gvx`
/// on 970 MiB and a core on more are each tuned to what they hold.
fn local(machine: Machine, run: &Path) -> Value {
	let memory = machine.memory_mb;
	let buffers = memory.div_ceil(4);
	// One twentieth of the disk in GiB, from 1 to 100, which the WAL and temporary files scale by
	// in tiny.yml; capped lower, since /data is every app's and not the database's alone.
	let twentieth = machine.disk_bytes.div_ceil(20 * 1024 * 1024 * 1024).clamp(1, 100);
	json!({
		"unix_socket_directories": run,
		"password_encryption": "scram-sha-256",
		"archive_mode": "on",
		"archive_command": "wal-g wal-push %p",
		// Every segment archived within a minute; see spec/architecture/databases.md, "Backups are
		// the data, kept off the cluster".
		"archive_timeout": 60,
		"wal_keep_size": "512MB",
		"shared_buffers": format!("{buffers}MB"),
		"maintenance_work_mem": format!("{}MB", buffers.div_ceil(4)),
		"effective_cache_size": format!("{}MB", memory.saturating_sub(buffers)),
		"work_mem": format!("{}MB", (buffers / MAX_CONNECTIONS).clamp(16, 256)),
		"max_parallel_workers": (machine.cpus / 2).max(1),
		"max_parallel_maintenance_workers": (machine.cpus * 33 / 100).max(1),
		"max_parallel_workers_per_gather": 0,
		"temp_file_limit": format!("{}GB", twentieth.min(TEMP_FILES_GB)),
		"min_wal_size": format!("{}GB", twentieth.min(MIN_WAL_GB)),
		"max_wal_size": format!("{}GB", (twentieth * 4).min(MAX_WAL_GB)),
	})
}

/// The keeper and the operator as the superuser on the socket by peer; everything over the network
/// by password, since the firewall already keeps it to the tailnet and Docker's NAT can rewrite
/// where a connection seems to come from.
fn pg_hba() -> Vec<String> {
	vec![
		format!("local all {SUPERUSER} peer"),
		format!("local replication {SUPERUSER} peer"),
		"host all all 0.0.0.0/0 scram-sha-256".into(),
		"host all all ::/0 scram-sha-256".into(),
		"host replication all 0.0.0.0/0 scram-sha-256".into(),
		"host replication all ::/0 scram-sha-256".into(),
	]
}

/// A string literal as SQL writes it.
pub fn literal(value: &str) -> String {
	format!("'{}'", value.replace('\'', "''"))
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::path::PathBuf;

	/// A member of 512 MiB and two cores on a disk of 44 GiB, as the containers run.
	const SMALL: Machine = Machine { memory_mb: 512, cpus: 2, disk_bytes: 44 * 1024 * 1024 * 1024 };

	fn config(node: &str, priority: u32) -> Config {
		Config {
			node: node.into(),
			peers: [("tyo", "100.64.0.1"), ("rdu", "100.64.0.3"), ("buf", "100.64.0.2")]
				.into_iter()
				.map(|(name, address)| (name.to_owned(), address.to_owned()))
				.collect(),
			quorum: vec!["100.64.0.1".into(), "100.64.0.3".into(), "100.64.0.2".into()],
			priority,
			superuser_password: "it's \"super\"".into(),
			replication_password: "copy".into(),
			patroni_password: "rest".into(),
			data: "/var/lib/postgresql/data".into(),
		}
	}

	#[test]
	fn each_member_is_reached_at_its_own_address_and_finds_every_etcd_member() {
		let (data, run) = (PathBuf::from("/var/lib/postgresql/data"), PathBuf::from("/tmp"));
		let rendered = patroni(&config("rdu", 2), SMALL, &data, &run);
		assert_eq!(rendered["name"], "rdu");
		assert_eq!(rendered["restapi"]["connect_address"], "100.64.0.3:8008");
		assert_eq!(rendered["postgresql"]["connect_address"], "100.64.0.3:5432");
		assert_eq!(
			rendered["etcd3"]["hosts"],
			json!(["100.64.0.1:2379", "100.64.0.3:2379", "100.64.0.2:2379"])
		);
		assert_eq!(rendered["etcd3"]["username"], "patroni");
		assert_eq!(rendered["tags"]["failover_priority"], 2);
		assert_eq!(rendered["tags"]["nofailover"], false);
		let sha = patroni(&config("sha", 0), SMALL, &data, &run);
		assert_eq!(
			sha["tags"],
			json!({ "failover_priority": 0, "nofailover": true, "clonefrom": true })
		);
		assert_eq!(rendered["postgresql"]["config_dir"], "/tmp/postgresql");
		assert_eq!(rendered["postgresql"]["parameters"]["unix_socket_directories"], "/tmp");
	}

	#[test]
	fn the_lease_fences_and_a_laggard_is_never_promoted() {
		let rendered = patroni(&config("tyo", 3), SMALL, Path::new("/d"), Path::new("/r"));
		let dcs = &rendered["bootstrap"]["dcs"];
		let (ttl, wait, retry) = (
			dcs["ttl"].as_u64().unwrap(),
			dcs["loop_wait"].as_u64().unwrap(),
			dcs["retry_timeout"].as_u64().unwrap(),
		);
		assert!(ttl >= wait + 2 * retry, "{ttl} {wait} {retry}");
		assert_eq!(dcs["maximum_lag_on_failover"], 1_048_576);
		assert_eq!(
			(dcs["primary_start_timeout"].clone(), dcs["synchronous_mode"].clone()),
			(json!(25), json!(false))
		);
		assert_eq!(dcs["failsafe_mode"], true);
		assert_eq!(dcs["postgresql"]["use_pg_rewind"], true);
		assert_eq!(dcs["postgresql"]["remove_data_directory_on_rewind_failure"], true);
		assert_eq!(rendered["postgresql"]["create_replica_methods"], json!(["wal_g", "basebackup"]));
		assert_eq!(rendered["watchdog"]["mode"], "off");
	}

	#[test]
	fn each_member_is_sized_from_what_it_holds_and_shares_what_must_agree() {
		let small = patroni(&config("gvx", 0), SMALL, Path::new("/d"), Path::new("/r"));
		let local = &small["postgresql"]["parameters"];
		assert_eq!(local["shared_buffers"], "128MB");
		assert_eq!(local["effective_cache_size"], "384MB");
		assert_eq!(local["maintenance_work_mem"], "32MB");
		assert_eq!(local["work_mem"], "16MB");
		assert_eq!(
			(
				local["min_wal_size"].clone(),
				local["max_wal_size"].clone(),
				local["temp_file_limit"].clone()
			),
			(json!("2GB"), json!("8GB"), json!("3GB"))
		);
		let large = Machine { memory_mb: 4096, cpus: 4, disk_bytes: 200 * 1024 * 1024 * 1024 };
		let tyo = patroni(&config("tyo", 3), large, Path::new("/d"), Path::new("/r"));
		assert_eq!(tyo["postgresql"]["parameters"]["shared_buffers"], "1024MB");
		assert_eq!(tyo["postgresql"]["parameters"]["max_parallel_workers"], 2);
		// What every member must agree on is in etcd, the same whatever the member holds.
		assert_eq!(small["bootstrap"]["dcs"], tyo["bootstrap"]["dcs"]);
		assert_eq!(small["bootstrap"]["dcs"]["postgresql"]["parameters"]["max_connections"], 50);
	}

	#[test]
	fn reads_the_ceiling_a_container_has() {
		let meminfo = "MemTotal:        3995132 kB\nMemFree:  100 kB\n";
		assert_eq!(memory_mb(Some("536870912\n"), meminfo), 512);
		// Half the machine, where the ceiling is above it: a node of 970 MiB is sized as 485.
		assert_eq!(memory_mb(Some("max\n"), meminfo), 1950);
		assert_eq!(memory_mb(Some("8589934592\n"), "MemTotal: 993280 kB\n"), 485);
		assert_eq!(memory_mb(None, ""), 512);
	}

	#[test]
	fn secrets_are_escaped_and_the_network_needs_a_password() {
		let rendered = patroni(&config("tyo", 3), SMALL, Path::new("/d"), Path::new("/r"));
		// Through serde: the quotes survive a round trip, as Patroni's YAML reader will see them.
		let text = serde_json::to_string(&rendered).unwrap();
		let back: Value = serde_json::from_str(&text).unwrap();
		assert_eq!(back["postgresql"]["authentication"]["superuser"]["password"], "it's \"super\"");
		let hba = rendered["postgresql"]["pg_hba"].as_array().unwrap();
		assert_eq!(hba[0], "local all postgres peer");
		assert!(!text.contains("trust"));
		assert_eq!(literal("it's"), "'it''s'");
	}
}
