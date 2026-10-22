/***
 * A build's WIT read as far as RFC kd7f9's subset, its exports, and a caller's calls matched one
 * layer down against a dependency's, 49qyg and vr5lw. The model's interface, `docs/code.md`.
 */

type primitive = [
  | #bool
  | #s8
  | #s16
  | #s32
  | #s64
  | #u8
  | #u16
  | #u32
  | #u64
  | #f32
  | #f64
  | #char
  | #string
]

/** A type with every alias resolved, a named one keeping its name, which no match compares. */
type rec type_ =
  | Primitive(primitive)
  | List(type_)
  | Option(type_)
  | Tuple(array<type_>)
  /** A result, its success's payload and its failure's, each absent where it carries none. */
  | Result({success: option<type_>, failure: option<type_>})
  | Record({name: string, fields: array<field>})
  | Variant({name: string, cases: array<case>})
  | Enum({name: string, cases: array<string>})
  | Flags({name: string, flags: array<string>})
and field = {name: string, type_: type_}
and case = {label: string, payload: option<type_>}

/** A parameter, its name the WIT's, which no match compares. */
type parameter = {name: string, type_: type_}

/**
 * A function by the name a call gives it, `{function}` for a world's own and
 * `{interface}.{function}` for one of an interface the world imports or exports.
 */
type function = {name: string, parameters: array<parameter>, result: option<type_>}

/** A package line's name, `{namespace}:{name}` and its version where it gives one. */
type package = {namespace: string, name: string, version: option<string>}

/** A world read, every name in it unique and every type it uses defined and not recursive. */
type t

/** What WIT has and the subset does not take. */
type construct =
  | Resource
  | Own
  | Borrow
  | Include
  /** A use, an import or an export of another package's interface, by its path. */
  | Foreign(string)
  /** Anything else the subset does not take, by a word for it, `map` or `async` or `@since`. */
  | Beyond(string)

/** Why a file is no world. */
type problem =
  /** A construct the subset refuses, every one found. */
  | Refused(construct)
  /** A token where the grammar asks for another, absent at the end, after which nothing is read. */
  | Unexpected({found: option<string>, expected: string})
  /** A name that is no kebab-case label. */
  | Name(string)
  /** A character WIT forbids, a control one or a bidirectional override, by its code point. */
  | Character(int)
  /** A type or an interface named and not defined. */
  | Undefined(string)
  /** A name defined twice where it must be once. */
  | Repeated(string)
  /** A type reached again from within itself. */
  | Recursive(string)
  /** An option within an option, which neither JSON nor CBOR tells from none, vr5lw. */
  | Nested
  /** No world where the file ends. */
  | NoWorld
  /** A world past the first. */
  | SecondWorld

/** A problem where it is, its line and column counted from 1, a column in code points. */
type refusal = {problem: problem, line: int, column: int}

/** The world a file of WIT holds, or every refusal of it in the order of where each is. */
let read: string => result<t, array<refusal>>

let package: t => option<package>

/** The world's name. */
let name: t => string

/** What the world imports, which are the calls it may make, in the order it declares them. */
let imports: t => array<function>

/** What the world exports, in the order it declares them. */
let exports: t => array<function>

/** A step from a function into its types, its parameters and its items counted from 0. */
type step =
  | Parameter(int)
  | Returned
  | Field(string)
  /** A variant's case, or an enum's or a flag's, by its name. */
  | Case(string)
  | Element
  | Item(int)
  | Present
  | Success
  | Failure

/** Why a call does not match, by the function it names. */
type mismatch =
  /** A call the caller's world imports nothing of. */
  | Undeclared(string)
  /** A call no export answers to. */
  | Missing(string)
  /** The parameters counted apart, the caller's and the export's. */
  | Count({call: string, caller: int, export: int})
  /** Two types apart where the steps lead, a parameter's held exactly. */
  | Mistyped({call: string, at: array<step>})
  /** A case or a flag the export's result names that the caller's type there does not hold. */
  | Unheld({call: string, at: array<step>, case: string})

/**
 * Whether each call matches the export of its name, every mismatch named in the order of the calls,
 * never by values and no layer further down, kd7f9.
 */
let matches: (t, ~calls: array<string>, ~exports: array<function>) => result<unit, array<mismatch>>
