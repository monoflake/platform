//! A control group read from the files the kernel wrote for a container, and from the same files
//! spoiled.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

mod common;

use common::root;
use driver_machine_management::{Group, ReadGroup, Unread};
use std::fs;
use std::path::{Path, PathBuf};

// The fixtures keep the container's files in `sys/fs/cgroup` itself, so its path is empty.
const CONTAINER: &str = "";

/// A copy of the first reading's group in a fresh root, with one file replaced.
fn spoiled(name: &str, file: &str, content: Option<&str>) -> PathBuf {
	let top = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(name);
	let directory = top.join("sys/fs/cgroup").join(CONTAINER);
	fs::create_dir_all(&directory).unwrap();
	let source = root("first").join("sys/fs/cgroup").join(CONTAINER);
	for entry in fs::read_dir(&source).unwrap() {
		let entry = entry.unwrap();
		fs::copy(entry.path(), directory.join(entry.file_name())).unwrap();
	}
	match content {
		Some(text) => fs::write(directory.join(file), text).unwrap(),
		None => fs::remove_file(directory.join(file)).unwrap(),
	}
	top
}

fn malformed(result: Result<Group, Unread>, file: &str, line: usize) {
	match result {
		Err(Unread::Malformed { file: got, line: at, .. }) => {
			assert_eq!(got, Path::new("sys/fs/cgroup").join(file));
			assert_eq!(at, line);
		}
		other => panic!("expected line {line} of {file} malformed, got {other:?}"),
	}
}

#[test]
fn a_container_is_read_from_its_directory() {
	let group = Group::read(&root("first"), Path::new(CONTAINER)).unwrap();
	assert_eq!(
		group,
		Group {
			path: PathBuf::from(CONTAINER),
			cpu_microseconds: 83_843,
			memory: 1_839_104,
			memory_limit: None,
			read_bytes: 1_474_560,
			written_bytes: 41_943_040,
			tasks: 1,
		}
	);
	let later = Group::read(&root("second"), Path::new("/")).unwrap();
	assert_eq!(later.cpu_microseconds, 151_521);
	assert_eq!(later.written_bytes, 83_886_080);
}

#[test]
fn a_missing_file_is_missing_under_the_root() {
	let root = root("first");
	match Group::read(&root, Path::new("gone")) {
		Err(Unread::Missing { file, .. }) => {
			assert_eq!(file, Path::new("sys/fs/cgroup/gone/io.stat"));
		}
		other => panic!("expected missing, got {other:?}"),
	}
	let without = spoiled("no-pids", "pids.current", None);
	match Group::read(&without, Path::new(CONTAINER)) {
		Err(Unread::Missing { file, .. }) => {
			assert_eq!(file, Path::new("sys/fs/cgroup/pids.current"));
		}
		other => panic!("expected missing, got {other:?}"),
	}
}

#[test]
fn a_limit_is_a_number_where_one_is_set() {
	let root = spoiled("limited", "memory.max", Some("268435456\n"));
	let group = Group::read(&root, Path::new(CONTAINER)).unwrap();
	assert_eq!(group.memory_limit, Some(268_435_456));
}

#[test]
fn io_is_summed_over_its_devices_and_empty_when_nothing_moved() {
	let two = "253:0 rbytes=100 wbytes=10 rios=1 wios=1 dbytes=0 dios=0\n8:16 rbytes=5 wbytes=20 rios=1 wios=1 dbytes=0 dios=0\n";
	let group = Group::read(&spoiled("io-two", "io.stat", Some(two)), Path::new(CONTAINER)).unwrap();
	assert_eq!((group.read_bytes, group.written_bytes), (105, 30));
	let group = Group::read(&spoiled("io-none", "io.stat", Some("")), Path::new(CONTAINER)).unwrap();
	assert_eq!((group.read_bytes, group.written_bytes), (0, 0));
}

#[test]
fn a_file_spoiled_is_malformed_at_its_line() {
	let read = |name: &str, file: &str, content: &str| {
		Group::read(&spoiled(name, file, Some(content)), Path::new(CONTAINER))
	};
	malformed(read("cpu-word", "cpu.stat", "user_usec 5\nusage_usec many\n"), "cpu.stat", 2);
	malformed(read("cpu-cut", "cpu.stat", "usage_usec\n"), "cpu.stat", 1);
	malformed(read("cpu-absent", "cpu.stat", "user_usec 5\nsystem_usec 6\n"), "cpu.stat", 3);
	malformed(read("mem-word", "memory.current", "lots\n"), "memory.current", 1);
	malformed(read("max-word", "memory.max", "unlimited\n"), "memory.max", 1);
	malformed(read("pids-word", "pids.current", "-1\n"), "pids.current", 1);
	malformed(read("io-cut", "io.stat", "253:0 rbytes=1\n"), "io.stat", 1);
	malformed(
		read("io-word", "io.stat", "253:0 rbytes=1 wbytes=2\n253:0 rbytes=x wbytes=2\n"),
		"io.stat",
		2,
	);
}
