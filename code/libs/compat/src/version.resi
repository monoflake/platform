/***
 * A version, RFC wnqvu: the frozen core, one integer raised only by a breaking change, compared by
 * its value; the range a reader reads; and the version a writer writes among the ranges of all that
 * read it. Where a version is carried is each format's own. The model's interface, `docs/code.md`;
 * `src/lib.rs` is the same in Rust.
 */

/**
 * The largest version, 2^53 - 1, JavaScript's largest safe integer, so both languages hold every
 * version exactly, decided by the author on 2026-10-20.
 */
let max: float

/** A version: an integer of 0 to `max`, its value read by `(v :> float)`. */
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
  /** Below its lowest: written in what it reads no longer. */
  | Older({version: t, range: range})
  /** Above its highest: written in what it does not yet read. */
  | Newer({version: t, range: range})

/** Whether the range reads the version. */
let reads: (range, t) => result<unit, refused>

/** Why no version can be written. */
type unchosen =
  /** No range was given. */
  | Empty
  /**
   * The lowest of every range's highest is below the lowest of each of these ranges, by their
   * positions as given, ascending: no version is read by all.
   */
  | Apart({highest: t, above: array<int>})

/**
 * What is written among the ranges of every reader running, the writer's own among them: the
 * lowest of their highest, which each reads, the same whatever their order, wnqvu.
 */
let written: array<range> => result<t, unchosen>
