//! What `model/contracts.json` holds that the Rust is written from, as the subset declares it,
//! `model/contracts/subset/subset.res`.

/// A primitive, the subset's `prim`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Prim {
	Bool,
	String,
	Float64,
	Int32,
	Uint32,
	Int53,
	Uint53,
	Bytes,
	Hash,
	Secret,
}

/// A field's shape. An id, of either half, is its integer alone on the wire, so its kind is not
/// kept.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum Shape {
	Prim(Prim),
	Id,
	Type(String),
	List(Box<Shape>),
	Map(Box<Shape>),
}

/// A record's or a case's field.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Field {
	pub(super) name: String,
	pub(super) key: i64,
	pub(super) shape: Shape,
	pub(super) optional: bool,
}

/// A choice of an enumeration, or a name of a set of names, its bit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Choice {
	pub(super) name: String,
	pub(super) code: i64,
}

/// A case of a union.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Case {
	pub(super) name: String,
	pub(super) code: i64,
	pub(super) fields: Vec<Field>,
}

/// What a type is.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum Def {
	Record(Vec<Field>),
	Enum { choices: Vec<Choice>, ordered: bool },
	Union { tag: String, cases: Vec<Case> },
	Flags(Vec<Choice>),
}

/// A type, by its name.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Declared {
	pub(super) name: String,
	pub(super) def: Def,
}

/// A reason an operation may fail for, its failure a choice of the type `failure`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Reason {
	pub(super) name: String,
	pub(super) failure: String,
}

/// An operation of an interface, its input and output by their types' names.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Operation {
	pub(super) name: String,
	pub(super) input: String,
	pub(super) output: String,
	pub(super) reasons: Vec<Reason>,
}

/// An interface.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Interface {
	pub(super) name: String,
	pub(super) version: u32,
	pub(super) operations: Vec<Operation>,
}

/// The contracts, each part in the order `model/contracts.json` is read in.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Model {
	pub(super) types: Vec<Declared>,
	pub(super) shell: Vec<Field>,
	pub(super) reasons: Vec<Reason>,
	pub(super) calling: Vec<Reason>,
	pub(super) interfaces: Vec<Interface>,
}
