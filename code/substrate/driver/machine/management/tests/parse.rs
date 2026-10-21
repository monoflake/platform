//! Every parser on what the test machine wrote, and on the same text cut or spoiled.

// What is here is all a test's, so the lints a test may break by are its helpers' as well.
#![cfg(test)]

mod common;

use common::{text, with_line};
use driver_machine_management::{
	Disk, Disks, Interface, Interfaces, Load, Memory, Parse, Processor, Quota, Quotas, Times, Unread,
};
use std::path::PathBuf;

fn malformed<T: std::fmt::Debug>(result: Result<T, Unread>, file: &str, line: usize) {
	match result {
		Err(Unread::Malformed { file: got, line: at, .. }) => {
			assert_eq!(got, PathBuf::from(file));
			assert_eq!(at, line);
		}
		other => panic!("expected line {line} of {file} malformed, got {other:?}"),
	}
}

#[test]
fn files_are_named_under_the_root() {
	assert_eq!(Processor::FILE, "proc/stat");
	assert_eq!(Load::FILE, "proc/loadavg");
	assert_eq!(Memory::FILE, "proc/meminfo");
	assert_eq!(Disks::FILE, "proc/diskstats");
	assert_eq!(Interfaces::FILE, "proc/net/dev");
}

#[test]
fn processor_reads_the_total_and_each_core() {
	let processor = Processor::parse(&text("first", "proc/stat")).unwrap();
	assert_eq!(
		processor.total,
		Times {
			user: 15998,
			nice: 5,
			system: 9330,
			idle: 1878110,
			iowait: 1128,
			irq: 1822,
			softirq: 1297,
			steal: 42
		}
	);
	assert_eq!(processor.cores.len(), 2);
	assert_eq!(
		processor.cores[1],
		Times {
			user: 8224,
			nice: 5,
			system: 4532,
			idle: 939207,
			iowait: 636,
			irq: 866,
			softirq: 446,
			steal: 19
		}
	);
	assert_eq!(processor.cores[0].idle, 938903);
}

#[test]
fn processor_refuses_a_line_cut_short_or_spoiled() {
	let stat = text("first", "proc/stat");
	malformed(Processor::parse(&with_line(&stat, 2, "cpu0 7773 0 4798")), "proc/stat", 2);
	malformed(
		Processor::parse(&with_line(&stat, 1, "cpu  15998 5 nine 1878110 1128 1822 1297 42")),
		"proc/stat",
		1,
	);
	malformed(
		Processor::parse(&with_line(&stat, 3, "cpu1 8224 5 4532 939207 636 866 446 -19")),
		"proc/stat",
		3,
	);
}

#[test]
fn processor_without_a_total_is_malformed_past_the_end() {
	malformed(Processor::parse("cpu0 1 2 3 4 5 6 7 8\nctxt 5\n"), "proc/stat", 3);
	malformed(Processor::parse(""), "proc/stat", 1);
}

#[test]
fn load_reads_three_averages() {
	let load = Load::parse(&text("second", "proc/loadavg")).unwrap();
	assert_eq!(load, Load { one: 0.28, five: 0.07, fifteen: 0.02 });
}

#[test]
fn load_refuses_a_short_line_a_word_and_a_non_number() {
	malformed(Load::parse("0.28 0.07\n"), "proc/loadavg", 1);
	malformed(Load::parse("0.28 busy 0.02 3/159 26286\n"), "proc/loadavg", 1);
	malformed(Load::parse("0.28 NaN 0.02 3/159 26286\n"), "proc/loadavg", 1);
	malformed(Load::parse(""), "proc/loadavg", 1);
}

#[test]
fn memory_reads_bytes_from_kilobytes() {
	let memory = Memory::parse(&text("first", "proc/meminfo")).unwrap();
	assert_eq!(
		memory,
		Memory {
			total: 3_496_348 * 1024,
			available: 2_951_356 * 1024,
			free: 1_120_276 * 1024,
			buffers: 236_932 * 1024,
			cached: 1_726_648 * 1024,
			swap_total: 0,
			swap_free: 0,
		}
	);
}

#[test]
fn memory_refuses_a_spoiled_line_and_a_missing_one() {
	let meminfo = text("first", "proc/meminfo");
	malformed(Memory::parse(&with_line(&meminfo, 1, "MemTotal:        lots kB")), "proc/meminfo", 1);
	malformed(Memory::parse(&with_line(&meminfo, 2, "MemFree:         1120276")), "proc/meminfo", 2);
	malformed(Memory::parse(&with_line(&meminfo, 4, "Buffers")), "proc/meminfo", 4);
	let lines = meminfo.lines().count();
	let without =
		meminfo.lines().filter(|l| !l.starts_with("SwapFree")).collect::<Vec<_>>().join("\n");
	malformed(Memory::parse(&without), "proc/meminfo", lines);
}

#[test]
fn disks_are_the_whole_ones_counted_in_bytes() {
	let disks = Disks::parse(&text("first", "proc/diskstats")).unwrap();
	assert_eq!(
		disks,
		Disks(vec![Disk {
			device: "vda".to_owned(),
			reads: 53983,
			read_bytes: 1_381_555 * 512,
			writes: 17580,
			written_bytes: 7_726_347 * 512,
		}])
	);
}

#[test]
fn disks_tell_a_partition_from_a_disk_by_its_name() {
	let line = |name: &str| format!(" 259 0 {name} 10 0 20 0 30 0 40 0 0 0 0 0 0 0 0\n");
	let names = |text: String| -> Vec<String> {
		Disks::parse(&text).unwrap().0.into_iter().map(|d| d.device).collect()
	};
	let all = [
		"sda",
		"sda1",
		"vdb",
		"vdb12",
		"xvda",
		"xvda1",
		"hdc",
		"hdc2",
		"nvme0n1",
		"nvme0n1p1",
		"nvme1n2p10",
		"mmcblk0",
		"mmcblk0p1",
		"dm-0",
		"md0",
		"loop3",
		"ram0",
		"zram0",
		"sr0",
		"fd0",
	];
	let text: String = all.iter().map(|n| line(n)).collect();
	assert_eq!(names(text), ["sda", "vdb", "xvda", "hdc", "nvme0n1", "mmcblk0", "dm-0", "md0"]);
}

#[test]
fn disks_refuse_a_line_cut_short_or_spoiled() {
	let stats = text("first", "proc/diskstats");
	malformed(Disks::parse(&with_line(&stats, 1, " 253 0 vda 53983 8879")), "proc/diskstats", 1);
	malformed(
		Disks::parse(&with_line(
			&stats,
			1,
			" 253 0 vda 53983 8879 many 11285 17580 123440 7726347 115583",
		)),
		"proc/diskstats",
		1,
	);
	malformed(Disks::parse(&with_line(&stats, 2, " 253 1")), "proc/diskstats", 2);
	malformed(
		Disks::parse(&with_line(&stats, 2, " 253 x vda1 22 0 176 2 0 0 0 0")),
		"proc/diskstats",
		2,
	);
}

#[test]
fn interfaces_leave_the_loopback_out() {
	let interfaces = Interfaces::parse(&text("first", "proc/net/dev")).unwrap();
	assert_eq!(
		interfaces,
		Interfaces(vec![
			Interface {
				name: "ens3".to_owned(),
				received_bytes: 824_595_144,
				received_packets: 144_128,
				received_errors: 0,
				received_dropped: 0,
				sent_bytes: 7_696_424,
				sent_packets: 54_155,
				sent_errors: 0,
				sent_dropped: 0,
			},
			Interface {
				name: "tailscale0".to_owned(),
				received_bytes: 2_035_740,
				received_packets: 2_626,
				received_errors: 0,
				received_dropped: 0,
				sent_bytes: 1_328_614,
				sent_packets: 1_969,
				sent_errors: 0,
				sent_dropped: 0,
			},
		])
	);
}

#[test]
fn interfaces_read_a_name_that_runs_into_its_counter() {
	let dev = text("first", "proc/net/dev");
	let wide = with_line(
		&dev,
		4,
		"averylongname0:824595144  144128    0    0    0     0          0         0  7696424   54155    0    0    0     0       0          0",
	);
	let interfaces = Interfaces::parse(&wide).unwrap();
	assert_eq!(interfaces.0[0].name, "averylongname0");
	assert_eq!(interfaces.0[0].received_bytes, 824_595_144);
}

#[test]
fn interfaces_refuse_a_line_cut_short_or_spoiled() {
	let dev = text("first", "proc/net/dev");
	malformed(
		Interfaces::parse(&with_line(&dev, 4, "  ens3: 824595144  144128    0    0")),
		"proc/net/dev",
		4,
	);
	malformed(
		Interfaces::parse(&with_line(
			&dev,
			5,
			"tailscale0: 2035740 packets 0 0 0 0 0 0 1328614 1969 0 0 0 0 0 0",
		)),
		"proc/net/dev",
		5,
	);
	malformed(Interfaces::parse(&with_line(&dev, 5, "tailscale0 2035740 2626")), "proc/net/dev", 5);
}

#[test]
fn quotas_read_every_row_and_its_limits() {
	let quotas = Quotas::parse(&text("first", "btrfs-qgroup-show")).unwrap();
	assert_eq!(quotas.0.len(), 15);
	assert_eq!(
		quotas.0[0],
		Quota { qgroup: "0/5".to_owned(), referenced: 4_415_488, exclusive: 4_415_488, limit: None }
	);
	assert_eq!(
		quotas.0[14],
		Quota { qgroup: "0/280".to_owned(), referenced: 81_920, exclusive: 81_920, limit: None }
	);
}

#[test]
fn quotas_read_a_limit_where_one_is_set() {
	let shown = text("first", "btrfs-qgroup-show");
	let limited = shown.replace(
		"0/257            16384        16384            none                 none",
		"0/257            16384        16384       1073741824                 none",
	);
	assert_ne!(limited, shown);
	let quotas = Quotas::parse(&limited).unwrap();
	assert_eq!(quotas.0[2].qgroup, "0/257");
	assert_eq!(quotas.0[2].limit, Some(1_073_741_824));
}

#[test]
fn quotas_refuse_a_row_cut_short_or_spoiled_and_a_header_that_is_not_the_one() {
	let shown = text("first", "btrfs-qgroup-show");
	malformed(Quotas::parse(&with_line(&shown, 5, "0/257            16384")), "btrfs-qgroup-show", 5);
	malformed(
		Quotas::parse(&with_line(
			&shown,
			5,
			"0/257            lots        16384            none                 none   x",
		)),
		"btrfs-qgroup-show",
		5,
	);
	malformed(
		Quotas::parse(&with_line(
			&shown,
			5,
			"0/257            16384        16384            some                 none   x",
		)),
		"btrfs-qgroup-show",
		5,
	);
	malformed(
		Quotas::parse(&with_line(&shown, 1, "Qgroupid    Referenced    Exclusive   Path")),
		"btrfs-qgroup-show",
		1,
	);
	malformed(Quotas::parse(""), "btrfs-qgroup-show", 1);
}
