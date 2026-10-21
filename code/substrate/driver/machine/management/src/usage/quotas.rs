//! The text of `btrfs qgroup show --raw -re <mount>`: a header, a rule, then a row for each qgroup.

use super::scan::{counter, lines, malformed};
use crate::{Parse, Quota, Quotas, Unread};

const HEADER: &str =
	"the header of `btrfs qgroup show --raw -re`, Qgroupid first and Max referenced in it";
const ROW: &str = "a qgroup id as 0/5, referenced, exclusive, max referenced and max exclusive, each a number or none";

/// A limit: a number, or `none`.
fn limit(word: &str) -> Option<Option<u64>> {
	if word == "none" { Some(None) } else { counter(word).map(Some) }
}

impl Parse for Quotas {
	const FILE: &'static str = "btrfs-qgroup-show";

	fn parse(text: &str) -> Result<Self, Unread> {
		let header = text.lines().next().unwrap_or("");
		if !header.starts_with("Qgroupid") || !header.contains("Max referenced") {
			return Err(malformed(Self::FILE, 1, HEADER));
		}
		let mut quotas = Vec::new();
		for (number, line) in lines(text).filter(|(number, _)| *number > 2) {
			if line.trim().is_empty() {
				continue;
			}
			let words: Vec<&str> = line.split_whitespace().collect();
			// The path that closes a row may hold spaces and is left unread.
			let [qgroup, referenced, exclusive, max_referenced, max_exclusive, ..] = words.as_slice()
			else {
				return Err(malformed(Self::FILE, number, ROW));
			};
			let parsed =
				(counter(referenced), counter(exclusive), limit(max_referenced), limit(max_exclusive));
			let (Some(referenced), Some(exclusive), Some(limit), Some(_)) = parsed else {
				return Err(malformed(Self::FILE, number, ROW));
			};
			if !qgroup.contains('/') {
				return Err(malformed(Self::FILE, number, ROW));
			}
			quotas.push(Quota { qgroup: (*qgroup).to_owned(), referenced, exclusive, limit });
		}
		Ok(Self(quotas))
	}
}
