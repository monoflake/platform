/***
 * A need compared with an allowance or an offer, RFCs 49qyg and kd7f9, reading no clock, store or
 * randomness. The model's interface, `docs/code.md`.
 */

/** A capability's value, one of the four `allowance-value` holds, an amount an integer. */
type value =
  | Flag(bool)
  | Amount(float)
  | One(string)
  | Subset(array<string>)

/**
 * A capability's type, yes or no, an amount, one of a set held against some of it, some of a set,
 * or a group of amounts, each member keyed `{name}.{member}`.
 */
type type_ = [
  | #flag
  | #amount
  | #one(array<string>)
  | #some(array<string>)
  | #amounts(array<string>)
]

/** A capability, its default what a side holding nothing of it holds. */
type entry = {name: string, type_: type_, default: value}

/** A vocabulary, each entry named once and its default of its type. */
type t

/** Why entries make no vocabulary, the first refused in their order. */
type malformed =
  /** A name or a member empty, or of other than lowercase ASCII letters, digits and hyphens. */
  | Name(string)
  /** Two entries of one name, or a set or a group holding a member twice. */
  | Repeated(string)
  /** An entry whose default is not of its type, by the entry's name. */
  | Default(string)

let make: array<entry> => result<t, malformed>

/** The vocabulary the model declares, as `model/contracts.json` holds it. */
let model: t

let entries: t => array<entry>

/** Who holds a value, the need or what it is compared with, an allowance or an offer. */
type side = Need | Held

/**
 * The values with each absent one its default, a group's for each member, others kept as given. A
 * need's one of a set has no default, and absent asks nothing.
 */
let filled: (t, side, dict<value>) => dict<value>

/** Why a capability fails, by its name or its group member's key. */
type failure =
  /** A need naming no entry nor any group's member. */
  | Unknown(string)
  /** A value not of its entry's type, a need's member outside its set among them. */
  | Mistyped({name: string, side: side})
  /** A need past what is held, both as filled. */
  | Exceeds({name: string, need: value, held: value})

/**
 * Whether a need fits an allowance, every capability that fails named once and sorted by name. Held
 * values the vocabulary does not name are passed over.
 */
let fits: (t, ~need: dict<value>, ~allowance: dict<value>) => result<unit, array<failure>>

/** Whether a need meets an offer, by the rules `fits` holds it to an allowance by. */
let meets: (t, ~need: dict<value>, ~offer: dict<value>) => result<unit, array<failure>>
