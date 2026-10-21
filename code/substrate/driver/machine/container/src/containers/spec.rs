//! A container's OCI runtime spec, built from its image's configuration, as containerd's own
//! default for Linux has it, with its network namespace joined and its capacity held by its cgroup.
//! https://github.com/opencontainers/runtime-spec/blob/main/config.md

use std::path::Path;

use serde_json::{Value, json};

use crate::{Capacity, ImageConfig, Refused};

/// Where a container's secrets are bound.
const SECRETS: &str = super::secrets::INSIDE;

/// The period a container's processor quota is counted over, in microseconds.
const PERIOD: u64 = 100_000;

/// The `PATH` a process is given where its image sets none, containerd's.
const PATH: &str = "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";

/// containerd's default capabilities.
const CAPABILITIES: [&str; 14] = [
	"CAP_CHOWN",
	"CAP_DAC_OVERRIDE",
	"CAP_FSETID",
	"CAP_FOWNER",
	"CAP_MKNOD",
	"CAP_NET_RAW",
	"CAP_SETGID",
	"CAP_SETUID",
	"CAP_SETFCAP",
	"CAP_SETPCAP",
	"CAP_NET_BIND_SERVICE",
	"CAP_SYS_CHROOT",
	"CAP_KILL",
	"CAP_AUDIT_WRITE",
];

const MASKED: [&str; 11] = [
	"/proc/acpi",
	"/proc/asound",
	"/proc/kcore",
	"/proc/keys",
	"/proc/latency_stats",
	"/proc/timer_list",
	"/proc/timer_stats",
	"/proc/sched_debug",
	"/proc/scsi",
	"/sys/firmware",
	"/sys/devices/virtual/powercap",
];

const READ_ONLY: [&str; 5] =
	["/proc/bus", "/proc/fs", "/proc/irq", "/proc/sys", "/proc/sysrq-trigger"];

/// Who a container's process runs as.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct User {
	pub(super) uid: u32,
	pub(super) gid: u32,
}

impl User {
	/// The image's `User`, `name`, `uid`, `name:group` or `uid:gid`, read against the container's own
	/// `/etc/passwd` and `/etc/group` where it names a name; root where it names none.
	pub(super) async fn resolve(user: Option<&str>, rootfs: &Path) -> Result<Self, Refused> {
		let user = user.unwrap_or_default();
		if user.is_empty() {
			return Ok(Self { uid: 0, gid: 0 });
		}
		let (name, group) = match user.split_once(':') {
			Some((n, g)) => (n, Some(g)),
			None => (user, None),
		};
		let passwd = read(rootfs, "etc/passwd").await;
		let entry = passwd.as_deref().and_then(|p| passwd_entry(p, name));
		let uid = match (name.parse::<u32>(), entry) {
			(Ok(uid), _) => uid,
			(Err(_), Some((uid, _))) => uid,
			(Err(_), None) => {
				return Err(Refused::new(
					"malformed",
					format!("the image's user {name} is in no /etc/passwd of it"),
				));
			}
		};
		let gid = match group {
			None => entry.map_or(0, |(_, gid)| gid),
			Some(group) => match group.parse::<u32>() {
				Ok(gid) => gid,
				Err(_) => read(rootfs, "etc/group")
					.await
					.as_deref()
					.and_then(|g| group_entry(g, group))
					.ok_or_else(|| {
						Refused::new(
							"malformed",
							format!("the image's group {group} is in no /etc/group of it"),
						)
					})?,
			},
		};
		Ok(Self { uid, gid })
	}
}

async fn read(rootfs: &Path, file: &str) -> Option<String> {
	tokio::fs::read_to_string(rootfs.join(file)).await.ok()
}

/// The uid and gid of a user, by its name or its uid, in a passwd file's lines,
/// `name:password:uid:gid:...`.
fn passwd_entry(passwd: &str, user: &str) -> Option<(u32, u32)> {
	passwd.lines().find_map(|line| {
		let mut fields = line.split(':');
		let name = fields.next()?;
		let uid = fields.nth(1)?;
		let gid = fields.next()?;
		(name == user || uid == user).then_some(())?;
		Some((uid.parse().ok()?, gid.parse().ok()?))
	})
}

/// The gid of a group by its name, in a group file's lines, `name:password:gid:...`.
fn group_entry(groups: &str, group: &str) -> Option<u32> {
	groups.lines().find_map(|line| {
		let mut fields = line.split(':');
		(fields.next()? == group).then_some(())?;
		fields.nth(1)?.parse().ok()
	})
}

/// What a container's spec is built of.
pub(super) struct Asked<'a> {
	pub(super) id: &'a str,
	pub(super) namespace: &'a str,
	pub(super) config: &'a ImageConfig,
	pub(super) user: User,
	/// What the deployment adds to its image's environment, each `NAME=value`, over the image's own.
	pub(super) env: &'a [String],
	pub(super) capacity: &'a Capacity,
	pub(super) netns: &'a Path,
	/// The directory of its secrets on the host, bound read-only at `/run/secrets`, where it has any.
	pub(super) secrets: Option<&'a Path>,
}

/// An environment with each of `over` set on it, the image's own entry of a name replaced.
fn environment(image: &[String], over: &[String]) -> Vec<String> {
	let name = |entry: &String| entry.split_once('=').map_or(entry.clone(), |(n, _)| n.to_owned());
	let mut env: Vec<String> = image.to_vec();
	if !env.iter().any(|e| e.starts_with("PATH=")) {
		env.insert(0, PATH.to_owned());
	}
	for entry in over {
		let n = name(entry);
		env.retain(|e| name(e) != n);
		env.push(entry.clone());
	}
	env
}

/// The spec, or why the image cannot run.
pub(super) fn build(asked: &Asked<'_>) -> Result<Value, Refused> {
	let args: Vec<&String> = asked.config.entrypoint.iter().chain(&asked.config.cmd).collect();
	if args.is_empty() {
		return Err(Refused::new("malformed", "the image names nothing to run"));
	}
	let cwd = asked.config.working_dir.as_deref().filter(|d| !d.is_empty()).unwrap_or("/");
	let memory = i64::try_from(asked.capacity.memory)
		.map_err(|_| Refused::new("beyond_host", "a container's memory is at most 2^63 - 1 bytes"))?;
	let cpu = match asked.capacity.millicores {
		0 => json!({ "period": PERIOD }),
		m => json!({ "period": PERIOD, "quota": u64::from(m) * PERIOD / 1000 }),
	};
	let mut mounts = vec![
		json!({ "destination": "/proc", "type": "proc", "source": "proc", "options": ["nosuid", "noexec", "nodev"] }),
		json!({
			"destination": "/dev",
			"type": "tmpfs",
			"source": "tmpfs",
			"options": ["nosuid", "strictatime", "mode=755", "size=65536k"],
		}),
		json!({
			"destination": "/dev/pts",
			"type": "devpts",
			"source": "devpts",
			"options": ["nosuid", "noexec", "newinstance", "ptmxmode=0666", "mode=0620", "gid=5"],
		}),
		json!({
			"destination": "/dev/shm",
			"type": "tmpfs",
			"source": "shm",
			"options": ["nosuid", "noexec", "nodev", "mode=1777", "size=65536k"],
		}),
		json!({
			"destination": "/dev/mqueue",
			"type": "mqueue",
			"source": "mqueue",
			"options": ["nosuid", "noexec", "nodev"],
		}),
		json!({ "destination": "/sys", "type": "sysfs", "source": "sysfs", "options": ["nosuid", "noexec", "nodev", "ro"] }),
		json!({
			"destination": "/sys/fs/cgroup",
			"type": "cgroup",
			"source": "cgroup",
			"options": ["nosuid", "noexec", "nodev", "relatime", "ro"],
		}),
		json!({
			"destination": "/run",
			"type": "tmpfs",
			"source": "tmpfs",
			"options": ["nosuid", "strictatime", "mode=755", "size=65536k"],
		}),
	];
	if let Some(secrets) = asked.secrets {
		mounts.push(json!({
			"destination": SECRETS,
			"type": "bind",
			"source": secrets,
			"options": ["rbind", "ro", "nosuid", "nodev", "noexec"],
		}));
	}
	Ok(json!({
		"ociVersion": "1.2.0",
		"process": {
			"terminal": false,
			"user": { "uid": asked.user.uid, "gid": asked.user.gid },
			"args": args,
			"env": environment(&asked.config.env, asked.env),
			"cwd": cwd,
			"capabilities": {
				"bounding": CAPABILITIES,
				"effective": CAPABILITIES,
				"permitted": CAPABILITIES,
			},
			"rlimits": [{ "type": "RLIMIT_NOFILE", "hard": 1024, "soft": 1024 }],
			"noNewPrivileges": true,
		},
		"root": { "path": "rootfs", "readonly": false },
		"hostname": asked.id,
		"mounts": mounts,
		"linux": {
			"resources": {
				"devices": [{ "allow": false, "access": "rwm" }],
				"cpu": cpu,
				"memory": { "limit": memory, "swap": memory },
			},
			"cgroupsPath": format!("/{}/{}", asked.namespace, asked.id),
			"namespaces": [
				{ "type": "pid" },
				{ "type": "ipc" },
				{ "type": "uts" },
				{ "type": "mount" },
				{ "type": "network", "path": asked.netns },
			],
			"maskedPaths": MASKED,
			"readonlyPaths": READ_ONLY,
		},
	}))
}
