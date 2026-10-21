/***
 * Features, RFC wnqvu, what a version cannot say, which both sides must support. The model's
 * interface, `docs/code.md`.
 */

/**
 * A side's features, those it has and those of them it needs, each list sorted and each name once.
 */
type t = private {has: array<string>, needs: array<string>}

/** Why a side's features were not made. */
type malformed =
  /** A name empty, or holding anything but lowercase ASCII letters, digits and hyphens. */
  | Name(string)
  /** A name needed, yet not had. */
  | Unheld(string)

/** The features with each list sorted and its repeats dropped, or the first name refused. */
let make: (~has: array<string>, ~needs: array<string>) => result<t, malformed>

/** Why two sides do not agree, what the first needs and the second has not, and the reverse. */
type missing = {first: array<string>, second: array<string>}

/** What both have, sorted, or what either needs and the other has not. */
let agreed: (t, t) => result<array<string>, missing>
