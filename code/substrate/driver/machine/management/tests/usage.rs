//! `Usage` read whole from a root, and the rates between the test machine's two readings.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

mod common;

use common::{at, near, root, text};
use driver_machine_management::{
	Between, Busy, Disks, Interfaces, Parse, ReadUsage, Unread, Usage,
};
use std::fs;
use std::path::PathBuf;

fn usage(reading: &str) -> Usage {
	Usage::read(&root(reading), &[], at(reading)).unwrap()
}

#[test]
fn a_machine_is_read_whole_from_a_root() {
	let usage = usage("first");
	assert_eq!(usage.at, at("first"));
	assert_eq!(usage.processor.cores.len(), 2);
	assert_eq!(usage.load.one, 0.13);
	assert_eq!(usage.memory.total, 3_496_348 * 1024);
	assert_eq!(usage.disks, Disks::parse(&text("first", "proc/diskstats")).unwrap());
	assert_eq!(usage.interfaces, Interfaces::parse(&text("first", "proc/net/dev")).unwrap());
	assert!(usage.spaces.is_empty());
}

#[test]
fn the_space_of_a_mount_is_read_under_the_root() {
	let mounts = [PathBuf::from("/"), PathBuf::from("/sys")];
	let usage = Usage::read(&root("first"), &mounts, 1).unwrap();
	assert_eq!(usage.spaces.len(), 2);
	assert_eq!(usage.spaces[1].path, PathBuf::from("/sys"));
	for space in &usage.spaces {
		assert!(space.total > 0);
		assert!(space.free <= space.total);
		assert!(space.available <= space.free);
	}
}

#[test]
fn a_mount_that_is_not_there_is_missing() {
	match Usage::read(&root("first"), &[PathBuf::from("/nowhere")], 1) {
		Err(Unread::Missing { file, .. }) => assert_eq!(file, PathBuf::from("nowhere")),
		other => panic!("expected missing, got {other:?}"),
	}
}

#[test]
fn a_file_missing_or_spoiled_names_itself() {
	let top = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join("usage-root");
	// A root left by an earlier run holds files this test means to find absent.
	let _ = fs::remove_dir_all(&top);
	fs::create_dir_all(top.join("proc/net")).unwrap();
	match Usage::read(&top, &[], 1) {
		Err(Unread::Missing { file, .. }) => assert_eq!(file, PathBuf::from("proc/stat")),
		other => panic!("expected missing, got {other:?}"),
	}
	fs::write(top.join("proc/stat"), text("first", "proc/stat")).unwrap();
	fs::write(top.join("proc/loadavg"), "0.1 x 0.3\n").unwrap();
	match Usage::read(&top, &[], 1) {
		Err(Unread::Malformed { file, line, .. }) => {
			assert_eq!(file, PathBuf::from("proc/loadavg"));
			assert_eq!(line, 1);
		}
		other => panic!("expected malformed, got {other:?}"),
	}
}

#[test]
fn rates_between_the_two_readings_of_the_machine() {
	let (first, second) = (usage("first"), usage("second"));
	let rates = second.since(&first).unwrap();
	let seconds = f64::from(u32::try_from(at("second") - at("first")).unwrap()) / 1000.0;
	assert!(near(rates.seconds, seconds));
	assert!(near(seconds, 3.798));

	// 144 user, 607 system, 5 irq, 1 softirq against 3 idle and 1 iowait.
	let (total, cores) = rates.busy;
	assert!(near(total.0, 757.0 / 761.0));
	assert_eq!(cores.len(), 2);
	// Core 0 has 73 user, 304 system, 2 irq and 1 softirq against no idle at all.
	assert!(near(cores[0].0, 1.0));
	for Busy(share) in cores.iter().copied().chain([total]) {
		assert!((0.0..=1.0).contains(&share));
	}

	assert_eq!(rates.disks.len(), 1);
	assert_eq!(rates.disks[0].0, "vda");
	assert!(near(rates.disks[0].1, 0.0));
	assert!(near(rates.disks[0].2, (8_217_867.0 - 7_726_347.0) * 512.0 / seconds));

	assert_eq!(rates.interfaces.len(), 2);
	assert_eq!(rates.interfaces[0].0, "ens3");
	assert!(near(rates.interfaces[0].1, (824_595_895.0 - 824_595_144.0) / seconds));
	assert!(near(rates.interfaces[0].2, (7_697_627.0 - 7_696_424.0) / seconds));
	assert_eq!(rates.interfaces[1].0, "tailscale0");
}

#[test]
fn nothing_is_earlier_than_itself_or_later_than_what_follows() {
	let (first, second) = (usage("first"), usage("second"));
	assert!(first.since(&first).is_none());
	assert!(first.since(&second).is_none());
}

#[test]
fn a_counter_that_went_back_counts_from_zero() {
	let (first, second) = (usage("first"), usage("second"));
	let mut later = second.clone();
	later.interfaces.0[0].received_bytes = 400;
	later.interfaces.0[0].sent_bytes = first.interfaces.0[0].sent_bytes;
	later.disks.0[0].written_bytes = 1_000;
	later.processor.total.idle = 0;
	later.processor.total.iowait = 0;
	let rates = later.since(&first).unwrap();
	assert!(near(rates.interfaces[0].1, 400.0 / rates.seconds));
	assert!(near(rates.interfaces[0].2, 0.0));
	assert!(near(rates.disks[0].2, 1_000.0 / rates.seconds));
	// Both idle counters restarted at zero, so neither is counted and all that grew was busy.
	assert!(near(rates.busy.0.0, 1.0));
}

#[test]
fn a_device_in_one_reading_alone_is_left_out() {
	let (first, second) = (usage("first"), usage("second"));
	let mut earlier = first.clone();
	earlier.interfaces.0.remove(0);
	earlier.disks.0.clear();
	let mut later = second.clone();
	later.interfaces.0.push(driver_machine_management::Interface {
		name: "wg0".to_owned(),
		..second.interfaces.0[0].clone()
	});
	let rates = later.since(&earlier).unwrap();
	assert_eq!(rates.interfaces.len(), 1);
	assert_eq!(rates.interfaces[0].0, "tailscale0");
	assert!(rates.disks.is_empty());
}

#[test]
fn an_idle_machine_is_not_busy() {
	let first = usage("first");
	let mut later = first.clone();
	later.at += 1000;
	let rates = later.since(&first).unwrap();
	assert_eq!(rates.busy.0, Busy(0.0));
	assert!(near(rates.seconds, 1.0));
}
