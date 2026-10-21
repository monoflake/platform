//! [`Malformed`] made and placed, as `src/malformed.resi` holds it, each step out to the value read
//! put before it.

use crate::{Malformed, Step};

impl Malformed {
	/// What was expected, of the value being read itself.
	pub(crate) fn expected(what: impl Into<String>) -> Self {
		Self { at: Vec::new(), expected: what.into() }
	}

	/// The same, found within the value read by `step`.
	pub(crate) fn within(mut self, step: Step) -> Self {
		self.at.insert(0, step);
		self
	}
}
