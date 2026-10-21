//! `/proc/net/dev`: two header lines, then a line for each interface, `name:` and sixteen counters.

use super::scan::{counters, lines, malformed};
use crate::{Interface, Interfaces, Parse, Unread};

const EXPECTED: &str = "a name, a colon and sixteen counters";

/// The loopback, which carries nothing that left the machine.
const LOOPBACK: &str = "lo";

impl Parse for Interfaces {
	const FILE: &'static str = "proc/net/dev";

	fn parse(text: &str) -> Result<Self, Unread> {
		let mut interfaces = Vec::new();
		for (number, line) in lines(text).filter(|(number, _)| *number > 2) {
			if line.trim().is_empty() {
				continue;
			}
			let Some((name, rest)) = line.split_once(':') else {
				return Err(malformed(Self::FILE, number, EXPECTED));
			};
			// A name as wide as the column runs into its first counter, so the colon splits them.
			let name = name.trim();
			let Some(values) = counters(rest.split_whitespace()) else {
				return Err(malformed(Self::FILE, number, EXPECTED));
			};
			let [
				received_bytes,
				received_packets,
				received_errors,
				received_dropped,
				_,
				_,
				_,
				_,
				sent_bytes,
				sent_packets,
				sent_errors,
				sent_dropped,
				..,
			] = values.as_slice()
			else {
				return Err(malformed(Self::FILE, number, EXPECTED));
			};
			if name.is_empty() {
				return Err(malformed(Self::FILE, number, EXPECTED));
			}
			if name == LOOPBACK {
				continue;
			}
			interfaces.push(Interface {
				name: name.to_owned(),
				received_bytes: *received_bytes,
				received_packets: *received_packets,
				received_errors: *received_errors,
				received_dropped: *received_dropped,
				sent_bytes: *sent_bytes,
				sent_packets: *sent_packets,
				sent_errors: *sent_errors,
				sent_dropped: *sent_dropped,
			});
		}
		Ok(Self(interfaces))
	}
}
