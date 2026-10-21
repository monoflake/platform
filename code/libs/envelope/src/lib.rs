//! `envelope*`, `model/graph/libraries.res`, and this file its interface, the model's,
//! `docs/code.md`: the same contract as `src/malformed.resi` holds in ReScript. Whoever implements
//! it implements each trait here for the types it names, and never edits this file; envelope-
//! generator writes the module `contracts`, as `build.rs` runs it, `model/graph/tools.res`.
//!
//! Each type of `model/contracts.json` in Rust, its JSON and its CBOR as RFC fhg6w's subset writes
//! them, and each interface's operations. A value is written in one JSON and one CBOR, and read
//! back from them alone: a field a reader does not know is passed over, and anything else not as
//! its type writes it is [`Malformed`].

mod malformed;
/// What the module `contracts` is written with -- each shape's JSON and CBOR, base64url, hex --
/// the implementer's own to shape, as envelope-generator's Rust calls it.
mod wire;

/// Every type, interface and reason of `model/contracts.json`, written by envelope-generator.
///
/// - **A type** `bucket-kind` is `BucketKind`, implementing [`Encoded`]: a record a struct, every
///   field public and named as the contract names it, a Rust keyword as a raw identifier,
///   `r#type`, and an optional one an `Option`; an enumeration an enum without data, each choice
///   named in upper camel case, `best_effort` as `BestEffort`; a union an enum, each case so named
///   and holding its fields; and a set of names a struct holding the `u32` of its bits, with a
///   constant for each name in upper snake case, `Rights::READ`.
/// - **A shape** is as the subset's table says: `bool`, `String`, `f64`, `i32`, `u32` for an
///   unsigned 32-bit integer, [`Uint53`] and [`Int53`], `Vec<u8>` for bytes and for a secret,
///   `[u8; 32]` for a hash, `u32` for an id of either half, `Vec` for a list and `BTreeMap<String,
///   _>` for a map.
/// - **The shell** of every record, `contracts.json`'s `shell`, is `Shell`.
/// - **An interface** `object` is the module `interface::object`, holding `VERSION`, a `u32`, and
///   for each operation, `write`, a unit struct named in upper camel case, `Write`, implementing
///   [`Operation`]; and `Call`, an enum with a case for each operation, named as its struct and
///   holding its input, `Call::Write(ObjectWrite)`, implementing [`Called`], so a call read is held
///   to the type its operation names.
/// - **The reasons** every operation may fail for are `REASONS`, and those a call between apps
///   adds are `CALLING`, each a `&[Reason]`, every [`Reason`] with its message; and `message(name)`
///   gives any reason's default message by its name, none for a name no reason has.
/// - **By a type's name**, `json_to_cbor(name, json)` reads the JSON as that type and gives its
///   CBOR, and `cbor_to_json(name, cbor)` the reverse, each none for a name no type has; and **by an
///   interface's name**, `call_json_to_cbor(name, json)` reads the JSON as a call of it, an
///   [`Envelope`] of its `Call`, and `call_cbor_to_json(name, cbor)` the reverse: the samples of
///   `tests/codec/` are held by these.
pub mod contracts {
	include!(concat!(env!("OUT_DIR"), "/contracts.rs"));
}

/// A step from a value into what it holds: a record's or a union's field by its name, in JSON and
/// CBOR alike; a list's item by its index; a map's entry by its key.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Step {
	/// A field, by its name.
	Field(String),
	/// An item, by its index.
	Index(usize),
	/// An entry, by its key.
	Key(String),
}

/// Why a value was not read as its type, which an operation answers as `malformed`, RFC fhg6w:
/// where, by the steps from the value read, and what was expected there -- for bytes, the text,
/// "base64url, unpadded".
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

/// A call, every operation's body, `model/contracts.json`'s `call`, RFC fhg6w: an interface's call,
/// which names its operation and holds its input, and the capabilities it carries, each a COSE Sign1
/// as it was signed, none written absent. Implementing [`Encoded`] for every [`Called`]: read, its
/// `interface` is held to the call's, its `operation` chooses how its `input` is read, and an
/// operation the interface has not is [`Malformed`] at `operation`. A call a certificate makes is
/// signed whole by its caller, outside this crate.
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

/// A reason an operation may fail for, the failure a caller acts on, RFC 49qyg, and the message an
/// `error` carries for it unless the moment says more, `model/contracts.json`'s `messages`, RFC
/// ge55b.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Reason {
	/// Its name, as an `error` carries it.
	pub name: &'static str,
	/// What a caller acts on.
	pub failure: contracts::Failure,
	/// Its default message, for a person.
	pub message: &'static str,
}

/// An answer, every operation's, `model/contracts.json`'s `answer`, RFC ge55b: by `status`, the
/// operation's output as `data`, or an `error`, told apart by `status` alone. Implementing
/// [`Encoded`] for every `O` that is: read, a `status` neither case names is [`Malformed`] at
/// `status`.
#[derive(Debug, Clone, PartialEq)]
pub enum Answer<O> {
	/// `success`: the operation's output.
	Success(O),
	/// `error`: its failure, its reason and its message.
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
