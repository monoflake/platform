//! `envelope*`, this file its interface, the model's, `docs/code.md`, and the contract
//! `src/malformed.resi` holds. The module `contracts` is `docs/envelope.md`'s.

mod malformed;
/// What the module `contracts` is written with, each shape's JSON and CBOR, base64url and hex, as
/// envelope-generator's Rust calls it.
mod wire;

/// Every type, interface and reason of `model/contracts.json`, written by envelope-generator as
/// `docs/envelope.md` lays out.
pub mod contracts {
	include!(concat!(env!("OUT_DIR"), "/contracts.rs"));
}

/// A step from a value into what it holds, a field by its name, an item by its index or an entry by
/// its key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
	/// A field, by its name.
	Field(String),
	/// An item, by its index.
	Index(usize),
	/// An entry, by its key.
	Key(String),
}

/// Why a value was not read as its type, answered as `malformed`, RFC fhg6w, by where it stands and
/// what was expected there.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Malformed {
	/// The steps from the value read to what is not as its type writes it.
	pub at: Vec<Step>,
	/// What was expected there.
	pub expected: String,
}

/// An integer of 0 to 2^53 - 1, exact in a JavaScript number, as a time in milliseconds or a size;
/// made by [`Bounded::new`] alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Uint53(u64);

/// An integer of -(2^53 - 1) to 2^53 - 1, as SQLite's within the platform; made by
/// [`Bounded::new`] alone.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Int53(i64);

/// An integer held within its bounds; implemented for [`Uint53`] over `u64` and [`Int53`] over
/// `i64`.
pub trait Bounded<N>: Sized {
	/// The integer, or none outside the bounds.
	fn new(number: N) -> Option<Self>;
	/// Its value.
	fn get(self) -> N;
}

/// A value in its JSON and its CBOR; implemented for every type of [`contracts`].
pub trait Encoded: Sized {
	/// Its JSON.
	fn to_json(&self) -> serde_json::Value;
	/// The value its JSON writes, or why that is not one.
	fn from_json(json: &serde_json::Value) -> Result<Self, Malformed>;
	/// Its CBOR, which `codec` writes deterministically.
	fn to_cbor(&self) -> codec::Value;
	/// The value its CBOR writes, or why that is not one.
	fn from_cbor(cbor: &codec::Value) -> Result<Self, Malformed>;
}

/// A call, `model/contracts.json`'s `call`, an interface's call and the capabilities it carries,
/// RFC fhg6w. Read, an operation the interface has not is [`Malformed`].
#[derive(Debug, Clone, PartialEq)]
pub struct Envelope<C> {
	/// The operation and its input.
	pub call: C,
	/// The capabilities it carries.
	pub capabilities: Vec<Vec<u8>>,
}

/// An interface's call, by its operation; implemented for each interface's `Call` in [`contracts`].
pub trait Called: Sized {
	/// Its interface's name.
	const INTERFACE: &'static str;
	/// Its operation's name.
	fn operation(&self) -> &'static str;
	/// Its input's JSON.
	fn input_json(&self) -> serde_json::Value;
	/// Its input's CBOR.
	fn input_cbor(&self) -> codec::Value;
	/// The call to the operation named, its input read from JSON, or why it is not one.
	fn from_json(operation: &str, input: &serde_json::Value) -> Result<Self, Malformed>;
	/// The call to the operation named, its input read from CBOR, or why it is not one.
	fn from_cbor(operation: &str, input: &codec::Value) -> Result<Self, Malformed>;
}

/// A reason an operation may fail for, its failure, RFC 49qyg, and the message an `error` carries
/// for it, RFC ge55b.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Reason {
	/// Its name, as an `error` carries it.
	pub name: &'static str,
	/// What a caller acts on.
	pub failure: contracts::Failure,
	/// Its default message, for a person.
	pub message: &'static str,
}

/// An answer, `model/contracts.json`'s `answer`, the output as `data` or an `error` told apart by
/// `status` alone, RFC ge55b.
#[derive(Debug, Clone, PartialEq)]
pub enum Answer<O> {
	/// `success`, the operation's output.
	Success(O),
	/// `error`, its failure, its reason and its message.
	Error(contracts::Error),
}

/// An operation of an interface, reached at `POST /{interface}/{operation}`, RFC vr5lw;
/// implemented for each in [`contracts`].
pub trait Operation {
	/// Its input, the request's body.
	type Input: Encoded;
	/// Its output, the answer when it succeeds.
	type Output: Encoded;
	/// Its interface's name.
	const INTERFACE: &'static str;
	/// Its interface's version.
	const VERSION: u32;
	/// Its name.
	const NAME: &'static str;
	/// The reasons it may fail for of its own, past [`contracts`]' `REASONS`.
	const REASONS: &'static [Reason];
}
