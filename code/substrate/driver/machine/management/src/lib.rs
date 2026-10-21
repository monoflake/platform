//! `driver(machine)`'s management, `model/ground/drivers.res`, and this file its interface, the
//! model's, `docs/code.md`. Whoever implements it implements each trait here for the types it
//! names, in the private module `usage`, and never edits this file.
//!
//! Today it holds what a machine reports of itself, its usage, RFC vr5lw: every figure read from
//! the kernel as the kernel counts it, a counter as a counter and a size in bytes, so what is sent
//! and how often is decided apart from it, [C18]. The rest of management -- a binding's list of
//! capacity, its policy, `end` -- is written with the driver. Everything is read under a root given,
//! `/` on a machine and a directory of files as the kernel writes them in a test, so the readers run
//! anywhere and only `Usage::read` touches a machine.

use std::path::{Path, PathBuf};

mod usage;

/// Why a file was not read as the kernel writes it: which, the line, from 1, and what was expected
/// there; or that it could not be opened at all.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Unread {
	/// The file, under the root, could not be read.
	Missing {
		/// Its path under the root.
		file: PathBuf,
		/// The error, as the system gave it.
		error: String,
	},
	/// A line of it is not as the kernel writes it.
	Malformed {
		/// Its path under the root.
		file: PathBuf,
		/// The line, from 1.
		line: usize,
		/// What was expected there.
		expected: String,
	},
}

/// One core's time, or every core's summed, in the kernel's clock ticks since boot, `/proc/stat`'s
/// columns in its order.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Times {
	/// Running in user mode.
	pub user: u64,
	/// Running in user mode at a lowered priority.
	pub nice: u64,
	/// Running in the kernel.
	pub system: u64,
	/// Idle.
	pub idle: u64,
	/// Idle while waiting on I/O.
	pub iowait: u64,
	/// Serving interrupts.
	pub irq: u64,
	/// Serving soft interrupts.
	pub softirq: u64,
	/// Taken by the hypervisor for another guest.
	pub steal: u64,
}

/// The processor, `/proc/stat`: every core's times summed, and each core's, by its number.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Processor {
	/// The `cpu` line.
	pub total: Times,
	/// The `cpuN` lines, in order of N.
	pub cores: Vec<Times>,
}

/// The load, `/proc/loadavg`: runnable tasks averaged over one, five and fifteen minutes.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Load {
	/// Over a minute.
	pub one: f64,
	/// Over five.
	pub five: f64,
	/// Over fifteen.
	pub fifteen: f64,
}

/// Memory, `/proc/meminfo`, each in bytes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Memory {
	/// `MemTotal`.
	pub total: u64,
	/// `MemAvailable`: what a new process could take without swapping.
	pub available: u64,
	/// `MemFree`.
	pub free: u64,
	/// `Buffers`.
	pub buffers: u64,
	/// `Cached`.
	pub cached: u64,
	/// `SwapTotal`.
	pub swap_total: u64,
	/// `SwapFree`.
	pub swap_free: u64,
}

/// A disk's I/O since boot, a line of `/proc/diskstats`, its sectors counted as 512 bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Disk {
	/// The device's name, `vda`.
	pub device: String,
	/// Reads completed.
	pub reads: u64,
	/// Bytes read.
	pub read_bytes: u64,
	/// Writes completed.
	pub writes: u64,
	/// Bytes written.
	pub written_bytes: u64,
}

/// Every whole disk of `/proc/diskstats`; a partition, a loop device and a ram disk are not one.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Disks(pub Vec<Disk>);

/// A network interface's traffic since it came up, a line of `/proc/net/dev`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Interface {
	/// Its name, `eth0`, `tailscale0`.
	pub name: String,
	/// Bytes received.
	pub received_bytes: u64,
	/// Packets received.
	pub received_packets: u64,
	/// Errors receiving.
	pub received_errors: u64,
	/// Packets dropped receiving.
	pub received_dropped: u64,
	/// Bytes sent.
	pub sent_bytes: u64,
	/// Packets sent.
	pub sent_packets: u64,
	/// Errors sending.
	pub sent_errors: u64,
	/// Packets dropped sending.
	pub sent_dropped: u64,
}

/// Every interface of `/proc/net/dev` but the loopback.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Interfaces(pub Vec<Interface>);

/// A file system's space, as `statvfs` gives it for a mount point, in bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Space {
	/// The mount point, `/` or `/data`.
	pub path: PathBuf,
	/// Its size.
	pub total: u64,
	/// Free.
	pub free: u64,
	/// Free to a process that is not root.
	pub available: u64,
}

/// A control group's usage, cgroup v2's files in its directory, as a container's is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Group {
	/// Its directory under `/sys/fs/cgroup`.
	pub path: PathBuf,
	/// `cpu.stat`'s `usage_usec`.
	pub cpu_microseconds: u64,
	/// `memory.current`.
	pub memory: u64,
	/// `memory.max`, none where it says `max`.
	pub memory_limit: Option<u64>,
	/// `io.stat`'s `rbytes`, summed over its devices.
	pub read_bytes: u64,
	/// `io.stat`'s `wbytes`, summed over its devices.
	pub written_bytes: u64,
	/// `pids.current`.
	pub tasks: u64,
}

/// A btrfs qgroup's usage, as `btrfs qgroup show --raw -re` writes a row, in bytes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Quota {
	/// Its id, `0/257` or `1/1`.
	pub qgroup: String,
	/// Referenced.
	pub referenced: u64,
	/// Exclusive.
	pub exclusive: u64,
	/// `max_rfer`, none where it says `none`.
	pub limit: Option<u64>,
}

/// Every qgroup of a btrfs file system.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Quotas(pub Vec<Quota>);

/// A text as the kernel, or a tool, writes it, read; implemented for [`Processor`], [`Load`],
/// [`Memory`], [`Disks`], [`Interfaces`] and [`Quotas`].
pub trait Parse: Sized {
	/// The file it is read from, under the root, `proc/stat`; for [`Quotas`], the command's output,
	/// which no file holds, a name for its errors alone.
	const FILE: &'static str;
	/// The value its text writes, or the first line that is not as written.
	fn parse(text: &str) -> Result<Self, Unread>;
}

/// A control group read from its directory under a root; implemented for [`Group`].
pub trait ReadGroup: Sized {
	/// The group at `path`, under `/sys/fs/cgroup` beneath the root.
	fn read(root: &Path, path: &Path) -> Result<Self, Unread>;
}

/// Everything a machine reports at one moment.
#[derive(Debug, Clone, PartialEq)]
pub struct Usage {
	/// When it was read, in milliseconds since the epoch, the caller's clock.
	pub at: u64,
	/// The processor.
	pub processor: Processor,
	/// The load.
	pub load: Load,
	/// Memory.
	pub memory: Memory,
	/// Each disk.
	pub disks: Disks,
	/// Each interface.
	pub interfaces: Interfaces,
	/// Each file system's space, by the mount points asked.
	pub spaces: Vec<Space>,
}

/// A machine's usage read whole; implemented for [`Usage`].
pub trait ReadUsage: Sized {
	/// Every file under `root`, `/` on a machine, and the space of each of `mounts`, at `at`.
	fn read(root: &Path, mounts: &[PathBuf], at: u64) -> Result<Self, Unread>;
}

/// How busy one core was, or all, between two readings: a share of 0 to 1 of the ticks that were
/// not idle, I/O waits counted idle.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Busy(pub f64);

/// What moved between two readings, each per second.
#[derive(Debug, Clone, PartialEq)]
pub struct Rates {
	/// The seconds between them.
	pub seconds: f64,
	/// Every core's share summed, then each core's, in order.
	pub busy: (Busy, Vec<Busy>),
	/// Each disk's bytes read and written a second, by its device.
	pub disks: Vec<(String, f64, f64)>,
	/// Each interface's bytes received and sent a second, by its name.
	pub interfaces: Vec<(String, f64, f64)>,
}

/// The rates between an earlier reading and a later one; implemented for [`Usage`]. A counter that
/// went back -- a device or an interface that came again -- counts from zero, and a device in one
/// reading alone is left out.
pub trait Between {
	/// The rates from `earlier` to `self`, none where `self` is not later.
	fn since(&self, earlier: &Self) -> Option<Rates>;
}
