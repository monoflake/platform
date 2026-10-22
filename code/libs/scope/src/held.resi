/***
 * A scope as its organization's bundle holds it, its status and its allowance read from the issuer
 * section, RFCs vuanj and kd7f9, reading no clock. The model's interface, `docs/code.md`.
 */

/** A scope read from a bundle, which a reader keeps for as long as it holds that bundle. */
type t

/** Why a bundle holds no scope by the id asked, RFC b8hyu. */
type unheld =
  /** The bundle is another scope's, by the id it names. */
  | Other(float)
  /** The bundle holds no issuer section. */
  | Absent
  /** Its issuer section not one CBOR data item as `bundle-issuer` writes it, where it stands. */
  | Malformed(Envelope.Malformed.t)

/** The scope a bundle verified by capability* and decoded by envelope* holds, by its id. */
let read: (Envelope.Contracts.Bundle.t, ~scope: float) => result<t, unheld>

/** Whether the scope runs, `active` where its issuer section names no status. */
let status: t => Envelope.Contracts.ScopeStatus.t

/** What the scope may use, an entry of the model's vocabulary it leaves unset at its default. */
let allowance: t => dict<Vocabulary.Needs.value>

/** Why a need does not fit a scope, a scope not active failing as `scope-status` names it. */
type refused =
  | Suspended
  | Deleted
  /** A need past the allowance, every capability that fails named as `Needs.fits` names it. */
  | Unfit(array<Vocabulary.Needs.failure>)

/** Whether a need, as a record holds it, fits the scope by the model's vocabulary. */
let fits: (t, ~need: dict<Envelope.Contracts.AllowanceValue.t>) => result<unit, refused>
