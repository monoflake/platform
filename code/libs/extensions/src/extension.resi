/***
 * What both controls compute alike of the `extension` and `capacity` records, RFCs v7v3w, vr5lw
 * and kd7f9, reading no clock, store or randomness. The model's interface, `docs/code.md`.
 */
open Envelope

/** What a host declares of itself as it is bound, by its driver or by the code that knows it. */
type declared = {
  host: Contracts.ExtensionHost.t,
  levels: Contracts.Placement.t,
  place: Contracts.ExtensionPlace.t,
  address: bool,
}

/**
 * What a binding is made with past its host, the binding token and any other credential sealed by
 * the control. Levels and place set here are held in place of the host's.
 */
type binding = {
  endpoint: string,
  token: Uint8Array.t,
  relays: Contracts.ExtensionRelays.t,
  levels?: Contracts.Placement.t,
  place?: Contracts.ExtensionPlace.t,
  quota?: float,
  grace?: float,
  management?: Uint8Array.t,
  shell?: Uint8Array.t,
}

/** Why a binding is not made, the contracts' `invalid`. */
type unbound =
  /** A grace below zero or past a year, in seconds. */
  | Grace(float)
  /** Relays of `some` naming none, or one twice. */
  | Relays

/** A year in seconds, the longest grace, and a week, the grace where none is set. */
let year: float
let week: float

/**
 * A host's binding, its levels and place copied from what the host declares unless its own are
 * set, and none dismissed.
 */
let bind: (declared, binding) => result<Contracts.Extension.t, array<unbound>>

/** A binding's grace in force, its own, else its organization's, else a week, a year at most. */
let grace: (Contracts.Extension.t, ~organization: Contracts.Organization.t) => float

/** The quota in force on a binding, its own, else its organization's, else none, RFC 87lwb. */
let quota: (Contracts.Extension.t, ~organization: Contracts.Organization.t) => option<float>

/** What a set is to what it holds, which decides the rules its members compose by. */
type set =
  /** Hosts holding a deployment, any of which answers. */
  | Pool
  /** Hosts one of which answers at a time by a lease, a keyed container or a database's writer. */
  | Keyed
  /** Copies of what is kept, each on a store or a volume of its own. */
  | Copies

type member = {levels: Contracts.Placement.t, place: Contracts.ExtensionPlace.t}

/**
 * The levels a set composes to, each the higher of its lowest member's own and what its members at
 * `stable` and above compose to by their spread, vr5lw and RFC 87lwb; none for no member.
 */
let compose: (set, array<member>) => option<Contracts.Placement.t>

/** A `capacity` record by its id, each of its credentials as the BLAKE3 the control hashed. */
type listed = {id: float, capacity: Contracts.Capacity.t, hashes: array<Uint8Array.t>}

/** Why a list is no `management-apply`, the contracts' `invalid`, by an item's id. */
type unlisted =
  /** An id listed twice. */
  | Repeated(float)
  /** Hashes counted apart from the record's credentials, or other than one or two. */
  | Credentials(float)
  /** A hash of other than 32 bytes. */
  | Hash(float)
  /** A token of other than 32 bytes, by its place among the tokens from 0. */
  | Token(int)

/**
 * The list one extension's driver is sent, the items of that extension sorted by id and the others
 * passed over, with the binding's tokens in force where given. Every refusal is named.
 */
let apply: (
  array<listed>,
  ~extension: float,
  ~generation: float,
  ~tokens: array<Uint8Array.t>=?,
) => result<Contracts.ManagementApply.t, array<unlisted>>

/** What crosses of a loan, the lender's binding as it stands and the quota lent, nothing sealed. */
let lend: (Contracts.Extension.t, ~quota: float) => Contracts.AuthorityLoan.t

/**
 * The borrower's binding of a loan, bound as any host is with the loan's quota, its lender named
 * and no grace, management token or shell key of its own, RFC 87lwb.
 */
let borrow: (
  Contracts.AuthorityLoan.t,
  ~lender: Contracts.ExtensionLender.t,
  ~token: Uint8Array.t,
  ~relays: Contracts.ExtensionRelays.t,
) => result<Contracts.Extension.t, array<unbound>>
