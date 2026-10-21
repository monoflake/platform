/***
 * A version, one integer raised only by a breaking change, a reader's range and what a writer
 * writes, RFC wnqvu. The model's interface, `docs/code.md`.
 */

/** The largest version, 2^53 - 1, so both languages hold every version exactly. */
let max: float

/** A version, an integer of 0 to `max`, its value read by `(v :> float)`. */
type t = private float

/** The number as a version, or none where it is no integer of 0 to `max`. */
let make: float => option<t>

/**
 * The versions a reader reads, its lowest to its highest, both read; its highest is the most it
 * could write.
 */
type range = private {lowest: t, highest: t}

/** The range of the two, or none where the lowest is above the highest. */
let range: (t, t) => option<range>

/** Why a reader refuses a version. */
type refused =
  /** Below its lowest, written in what it reads no longer. */
  | Older({version: t, range: range})
  /** Above its highest, written in what it does not yet read. */
  | Newer({version: t, range: range})

/** Whether the range reads the version. */
let reads: (range, t) => result<unit, refused>

/** Why no version can be written. */
type unchosen =
  /** No range was given. */
  | Empty
  /**
   * No version is read by all, the lowest highest being below these ranges' lowest, by position.
   */
  | Apart({highest: t, above: array<int>})

/**
 * What is written among every running reader's ranges, the lowest of their highest, whatever their
 * order, wnqvu.
 */
let written: array<range> => result<t, unchosen>
