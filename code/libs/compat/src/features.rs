//! [`Featured`] for [`Features`]: what a version cannot say, held by both sides, RFC wnqvu.

use crate::{Featured, Features, Malformed, Missing};

/// Whether a name is one: not empty, and lowercase ASCII letters, digits and hyphens alone.
fn named(name: &str) -> bool {
	!name.is_empty()
		&& name.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
}

/// The names sorted, each once.
fn sorted(names: &[&str]) -> Vec<String> {
	let mut names: Vec<String> = names.iter().map(|n| (*n).to_owned()).collect();
	names.sort();
	names.dedup();
	names
}

/// What `needs` holds that `has` does not, in the order of `needs`.
fn lacked(needs: &[String], has: &[String]) -> Vec<String> {
	needs.iter().filter(|n| !has.contains(n)).cloned().collect()
}

impl Featured for Features {
	fn new(has: &[&str], needs: &[&str]) -> Result<Self, Malformed> {
		if let Some(name) = has.iter().find(|n| !named(n)) {
			return Err(Malformed::Name((*name).to_owned()));
		}
		for name in needs {
			if !named(name) {
				return Err(Malformed::Name((*name).to_owned()));
			}
			if !has.contains(name) {
				return Err(Malformed::Unheld((*name).to_owned()));
			}
		}
		Ok(Self { has: sorted(has), needs: sorted(needs) })
	}

	fn has(&self) -> &[String] {
		&self.has
	}

	fn needs(&self) -> &[String] {
		&self.needs
	}

	fn agreed(&self, other: &Self) -> Result<Vec<String>, Missing> {
		let missing =
			Missing { first: lacked(&self.needs, &other.has), second: lacked(&other.needs, &self.has) };
		if missing.first.is_empty() && missing.second.is_empty() {
			Ok(self.has.iter().filter(|n| other.has.contains(n)).cloned().collect())
		} else {
			Err(missing)
		}
	}
}
