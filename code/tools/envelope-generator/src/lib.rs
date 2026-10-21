//! `envelope-generator`, `model/graph/tools.res`, writing envelope*'s Rust for its `build.rs` as
//! `docs/envelope.md` lays out. This file is its interface, the model's.

mod generate;

/// `model/contracts.json`, read.
#[derive(Debug, Clone, PartialEq)]
pub struct Contracts(serde_json::Value);

/// Why the contracts were not read or written, where by names and indices joined by `/`, and what
/// was expected.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Unread {
	/// Where, from the top of `model/contracts.json`.
	pub at: String,
	/// What was expected there.
	pub expected: String,
}

/// The generator; implemented for [`Contracts`].
pub trait Generate: Sized {
	/// The contracts in the text, as `model/contracts.json` is written.
	fn read(text: &str) -> Result<Self, Unread>;
	/// envelope*'s Rust, one source the same for the same contracts, holding only what
	/// `docs/envelope.md` lists.
	fn rust(&self) -> Result<String, Unread>;
}
