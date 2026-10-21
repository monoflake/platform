//! `envelope-generator`, `model/graph/tools.res`, and this file its interface, the model's,
//! `docs/code.md`: the same contract as `src/generate.resi` holds in ReScript, a private module
//! beside it. Whoever implements it implements the trait for the type it names there, and never
//! edits this file.
//!
//! It reads `model/contracts.json` and writes envelope*'s Rust, one source the library's
//! `build.rs` writes into cargo's `OUT_DIR` and its `src/lib.rs` includes whole as its module
//! `contracts`. What that source holds, and every name in it, is said by that `src/lib.rs`.

mod generate;

/// `model/contracts.json`, read.
#[derive(Debug, Clone, PartialEq)]
pub struct Contracts(serde_json::Value);

/// Why the contracts were not read or written: where in them, as a path of names and indices
/// joined by `/`, and what was expected there.
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
	/// envelope*'s Rust: one source, the same for the same contracts byte for byte, holding no
	/// item but what the library's `src/lib.rs` says its module `contracts` holds.
	fn rust(&self) -> Result<String, Unread>;
}
