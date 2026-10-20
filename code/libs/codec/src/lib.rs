//! `codec*`, `model/graph/libraries.res`, and this file its interface, the model's, `docs/code.md`:
//! the same contract as `src/cbor.resi`, `src/sign1.resi` and `src/cwt.resi` hold in ReScript, a
//! private module beside each. Whoever implements it implements each trait for the type it names
//! there, and never edits this file.

mod cbor;
mod cwt;
mod sign1;

/// One CBOR data item, RFC 8949's data model.
///
/// An integer is any of -2^64 to 2^64 - 1, of major type 0 or 1 by its sign, and is never a float:
/// a float is kept as the `f64` it denotes, whichever width it was read at. A map keeps its pairs in
/// the order read, any value a key. A tag and a simple value are kept as they are written, a simple
/// value one of 0 to 19 and 32 to 255.
#[derive(Debug, Clone, PartialEq)]
pub enum Value {
	/// An integer of major type 0 or 1.
	Integer(i128),
	/// A byte string.
	Bytes(Vec<u8>),
	/// A text string.
	Text(String),
	/// An array.
	Array(Vec<Value>),
	/// A map, its pairs in the order read.
	Map(Vec<(Value, Value)>),
	/// A tag and its content.
	Tag(u64, Box<Value>),
	/// `false` or `true`.
	Bool(bool),
	/// `null`.
	Null,
	/// `undefined`.
	Undefined,
	/// Any other simple value.
	Simple(u8),
	/// A float of any width.
	Float(f64),
}

/// Why bytes were not read as one data item.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Refused {
	/// The input ended inside an item: RFC 8949 Appendix F's first kind.
	Truncated,
	/// Bytes were left after the one item: its second kind.
	Trailing,
	/// A syntax error, its third kind: a reserved value, a simple value below 32 in two bytes, a
	/// string chunk not a definite string of its own type, a break out of place, or additional
	/// information 31 on major type 0, 1 or 6.
	Syntax,
	/// Well formed yet not valid: text that is not UTF-8, or a map's key repeated, its 5.3 and 5.6.
	Invalid,
	/// Within more than [`DEPTH`] arrays, maps and tags, refused as soon as it is met, so no input can
	/// nest a reader into running out of its stack.
	TooDeep,
	/// Well formed and valid, yet not as 4.2.1 writes it: an indefinite length, a head or a float
	/// longer than it need be, a NaN but f97e00, or a map's keys out of the bytewise order of their
	/// encodings. Only [`Cbor::decode_deterministic`] refuses this.
	Nondeterministic,
}

/// Why a value could not be written, what [`Cbor::decode`] would refuse never being written.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Unwritable {
	/// An integer, a tag or a simple value out of its range.
	OutOfRange,
	/// A map holding two keys whose encodings are one.
	RepeatedKey,
	/// A value within more than [`DEPTH`] arrays, maps and tags.
	TooDeep,
}

/// How many arrays, maps and tags an item may stand within.
pub const DEPTH: usize = 128;

/// CBOR written as RFC 8949's 4.2.1 writes it, and read strictly; implemented for [`Value`].
pub trait Cbor: Sized {
	/// The value written as 4.2.1 writes it: definite lengths, every head and float in its shortest
	/// form, a NaN as f97e00, and every map's keys in the bytewise order of their encodings.
	fn encode(&self) -> Result<Vec<u8>, Unwritable>;
	/// Exactly one data item, well formed and valid.
	fn decode(bytes: &[u8]) -> Result<Self, Refused>;
	/// Exactly one data item, as [`Cbor::decode`] reads it, and only one [`Cbor::encode`] would write
	/// byte for byte.
	fn decode_deterministic(bytes: &[u8]) -> Result<Self, Refused>;
}

/// A COSE Sign1, RFC 9052's 4.2, as its four fields.
///
/// The signature is made and checked by what the caller gives, over [`CoseSign1::to_be_signed`];
/// this holds the structure alone.
#[derive(Debug, Clone, PartialEq)]
pub struct Sign1 {
	/// The protected header map as the bytes it was serialized to, RFC 9052's 3, an empty map as no
	/// bytes: kept as written, since the signature covers these bytes and not a map.
	pub protected: Vec<u8>,
	/// The unprotected header map, its pairs in the order read.
	pub unprotected: Vec<(Value, Value)>,
	/// None where the payload is detached, written as nil, its 4.1.
	pub payload: Option<Vec<u8>>,
	/// The signature.
	pub signature: Vec<u8>,
}

/// Why bytes were not read as a Sign1.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Sign1Refused {
	/// Not one CBOR data item, as [`Cbor::decode`] refuses it.
	Cbor(Refused),
	/// One data item, yet no Sign1: a tag other than 18; not an array of a byte string, a map, a byte
	/// string or nil, and a byte string; or protected bytes neither empty nor exactly one CBOR map.
	Shape,
}

/// COSE's Sign1 structure; implemented for [`Sign1`].
pub trait CoseSign1: Sized {
	/// The bytes a signature is made and checked over, the Sig_structure for "Signature1", RFC
	/// 9052's 4.4: its context, the protected bytes, the external additional data and the payload,
	/// written as [`Cbor::encode`] writes them. Protected bytes serializing an empty map, `h'a0'`,
	/// are written as no bytes, as RFC 9052's 3 has every computation take them.
	fn to_be_signed(protected: &[u8], aad: &[u8], payload: &[u8]) -> Vec<u8>;
	/// The Sign1 written as [`Cbor::encode`] writes, under tag 18 where `tagged`.
	fn encode(&self, tagged: bool) -> Result<Vec<u8>, Unwritable>;
	/// A Sign1, under tag 18 or under none, and whether it was tagged.
	fn decode(bytes: &[u8]) -> Result<(Self, bool), Sign1Refused>;
}

/// A CWT's claims set, RFC 8392: a CBOR map, its pairs in the order read; a claim's key is an
/// integer or a text, its 3. What a claim means is the caller's.
#[derive(Debug, Clone, PartialEq)]
pub struct Claims(pub Vec<(Value, Value)>);

/// Why bytes were not read as a CWT.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CwtRefused {
	/// Not under tag 61 nor anything else a Sign1, as [`CoseSign1::decode`] refuses it.
	Sign1(Sign1Refused),
	/// A Sign1 whose payload is detached, so it carries no claims.
	Detached,
	/// A payload that is not one CBOR data item, as [`Cbor::decode`] refuses it.
	Payload(Refused),
	/// A payload that is one data item, yet no map.
	Unclaimed,
}

/// A CWT carried as a Sign1, which may stand under CWT's tag 61; implemented for [`Claims`].
pub trait Cwt: Sized {
	/// The payload a Sign1 carries the claims as: the map written as [`Cbor::encode`] writes it.
	fn payload(&self) -> Result<Vec<u8>, Unwritable>;
	/// A CWT's Sign1 and its claims, from bytes under tags 61 and 18, 18 alone, or neither.
	fn decode(bytes: &[u8]) -> Result<(Sign1, Self), CwtRefused>;
}
