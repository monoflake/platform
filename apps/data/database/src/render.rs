//! Postgres's configuration, written afresh to the scratch directory on every start, so what runs
//! is what this file says and nothing an earlier start left behind.

use std::path::Path;

/// Postgres's own port, published to the tailnet. See spec/architecture/databases.md, "Where it
/// runs, and which one writes".
pub const PORT: u16 = 5432;
/// The role a standby copies and follows the primary as.
pub const REPLICATOR: &str = "replicator";
pub const SUPERUSER: &str = "postgres";

/// `postgresql.conf` for the cluster at `data`, its other files beside it in `run`. `follow` is
/// the primary's conninfo on a standby.
pub fn postgresql_conf(data: &Path, run: &Path, follow: Option<&str>) -> String {
	let mut lines = vec![
		setting("data_directory", &data.display().to_string()),
		setting("hba_file", &run.join("pg_hba.conf").display().to_string()),
		setting("ident_file", &run.join("pg_ident.conf").display().to_string()),
		setting("unix_socket_directories", &run.display().to_string()),
		setting("listen_addresses", "*"),
		format!("port = {PORT}"),
		setting("password_encryption", "scram-sha-256"),
		// Sized for a node of three gigabytes shared with everything else it runs.
		setting("shared_buffers", "128MB"),
		"max_connections = 50".into(),
		"max_worker_processes = 4".into(),
		"max_parallel_workers = 2".into(),
		"max_parallel_workers_per_gather = 1".into(),
		"max_parallel_maintenance_workers = 1".into(),
		// Replication, and every segment archived within a minute. See spec/architecture/databases.md,
		// "Backups are the data, kept off the cluster".
		setting("wal_level", "replica"),
		"max_wal_senders = 10".into(),
		"max_replication_slots = 10".into(),
		setting("wal_keep_size", "512MB"),
		setting("hot_standby", "on"),
		setting("archive_mode", "on"),
		setting("archive_command", "wal-g wal-push %p"),
		"archive_timeout = 60".into(),
		// A standby that fell behind what the primary keeps catches up from the archive.
		setting("restore_command", "wal-g wal-fetch %f %p"),
		setting("recovery_target_timeline", "latest"),
	];
	if let Some(conninfo) = follow {
		lines.push(setting("primary_conninfo", conninfo));
	}
	lines.join("\n") + "\n"
}

/// The keeper and the operator as the superuser on the socket by peer; everything over the network
/// by password, since the firewall already keeps it to the tailnet and Docker's NAT can rewrite
/// where a connection seems to come from.
pub fn pg_hba() -> String {
	let lines = [
		format!("local all {SUPERUSER} peer"),
		format!("local replication {SUPERUSER} peer"),
		"host all all 0.0.0.0/0 scram-sha-256".into(),
		"host all all ::/0 scram-sha-256".into(),
		"host replication all 0.0.0.0/0 scram-sha-256".into(),
		"host replication all ::/0 scram-sha-256".into(),
	];
	lines.join("\n") + "\n"
}

/// A password file for libpq, any host on Postgres's port.
pub fn pgpass(entries: &[(&str, &str)]) -> String {
	entries
		.iter()
		.map(|(user, password)| format!("*:{PORT}:*:{}:{}\n", escaped(user), escaped(password)))
		.collect()
}

/// A libpq connection string to `host` as `user`, its password read from `passfile`.
pub fn conninfo(host: &str, user: &str, passfile: &Path, application: &str) -> String {
	[
		("host", host),
		("port", &PORT.to_string()),
		("user", user),
		("passfile", &passfile.display().to_string()),
		("application_name", application),
	]
	.iter()
	.map(|(key, value)| format!("{key}={}", quoted_value(value)))
	.collect::<Vec<_>>()
	.join(" ")
}

/// A string literal as SQL writes it.
pub fn literal(value: &str) -> String {
	format!("'{}'", value.replace('\'', "''"))
}

fn setting(key: &str, value: &str) -> String {
	format!("{key} = {}", literal(value))
}

/// pgpass escapes its separator and its escape.
fn escaped(value: &str) -> String {
	value.replace('\\', "\\\\").replace(':', "\\:")
}

/// A conninfo value in single quotes, its quotes and backslashes escaped.
fn quoted_value(value: &str) -> String {
	format!("'{}'", value.replace('\\', "\\\\").replace('\'', "\\'"))
}

#[cfg(test)]
mod tests {
	use super::*;
	use std::path::PathBuf;

	#[test]
	fn a_standby_follows_and_a_primary_does_not() {
		let (data, run) = (PathBuf::from("/var/lib/postgresql/data"), PathBuf::from("/tmp"));
		let primary = postgresql_conf(&data, &run, None);
		assert!(primary.contains("archive_command = 'wal-g wal-push %p'\n"));
		assert!(primary.contains("restore_command = 'wal-g wal-fetch %f %p'\n"));
		assert!(primary.contains("hba_file = '/tmp/pg_hba.conf'\n"));
		assert!(primary.contains("port = 5432\n"));
		assert!(!primary.contains("primary_conninfo"));
		let standby = postgresql_conf(&data, &run, Some("host='a' user='b'"));
		assert!(standby.contains("primary_conninfo = 'host=''a'' user=''b'''\n"));
	}

	#[test]
	fn the_network_needs_a_password_and_the_socket_is_the_superuser_alone() {
		let hba = pg_hba();
		assert!(hba.starts_with("local all postgres peer\n"));
		assert!(!hba.contains("trust"));
		assert_eq!(hba.matches("scram-sha-256").count(), 4);
		assert!(hba.contains("host replication all 0.0.0.0/0 scram-sha-256\n"));
	}

	#[test]
	fn secrets_are_escaped_where_they_are_written() {
		assert_eq!(pgpass(&[("replicator", "a:b\\c")]), "*:5432:*:replicator:a\\:b\\\\c\n");
		assert_eq!(literal("it's"), "'it''s'");
		let info = conninfo("100.64.0.1", "replicator", Path::new("/tmp/pgpass"), "buf");
		assert_eq!(
			info,
			"host='100.64.0.1' port='5432' user='replicator' passfile='/tmp/pgpass' \
			 application_name='buf'"
		);
	}
}
