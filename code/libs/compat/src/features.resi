/***
 * Features, RFC wnqvu: what a version cannot say, where a feature must be supported by both sides
 * and not merely passed over. Each side declares the features it has and which of them it needs the
 * other to have, and what both have is used, as RFC 49qyg compares a set. The model's interface,
 * `docs/code.md`; `src/lib.rs` is the same in Rust.
 */

/** A side's features: those it has, and those of them it needs; each list sorted, each name once. */
type t = private {has: array<string>, needs: array<string>}

/** Why a side's features were not made. */
type malformed =
  /** A name empty, or holding anything but lowercase ASCII letters, digits and hyphens. */
  | Name(string)
  /** A name needed, yet not had. */
  | Unheld(string)

/**
 * The features, each list sorted and its repeats dropped, or the first name refused: every name of
 * `has` in its order, then every one of `needs`.
 */
let make: (~has: array<string>, ~needs: array<string>) => result<t, malformed>

/** Why two sides do not agree: what the first needs and the second has not, and the reverse, each sorted. */
type missing = {first: array<string>, second: array<string>}

/** What both have, sorted, or what either needs and the other has not. */
let agreed: (t, t) => result<array<string>, missing>
