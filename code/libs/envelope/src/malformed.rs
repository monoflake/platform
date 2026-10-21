//! [`Malformed`] made and placed, as `src/malformed.resi` holds it in ReScript: a reader says what
//! it expected where it stands, and each step out to the value read is put before it on the way.

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
