/***
 * A journal, what cannot yet fill a parcel, sealed per write and exported as the parcel it becomes,
 * as RFC b8f35 lays it out. The model's interface, `docs/code.md`.
 */

/** 5 bytes, what a journal's first object begins with. */
let prefix: int

/** A write sealed, its object and the index of the segment the next write begins at. */
type written = {object: Uint8Array.t, next: int}

/**
 * Why a write was not sealed, the first of a bad key, master's version, seed or first segment,
 * nothing to seal or too much.
 */
type unsealable = Key | Master | Seed | First | Empty | Overfull

/** Why an object was not opened, the first of these, in their order, the prefix asked of the first
 * object alone, and the segments in their order. */
type unopened =
  /** A first segment below 0. */
  | First
  /** Shorter than its prefix. */
  | Prefix
  /** Revision 2, defined and not built. */
  | Reserved
  /** A revision undefined. */
  | Revision(int)
  /** A master's version of 0, or another than the header's. */
  | Master
  /** A key not of 32 bytes. */
  | Key
  /** No segment, or a last segment no longer than its tag. */
  | Length
  /** A segment whose tag does not hold, by its index. */
  | Tag(int)

/**
 * A write sealed from segment `first` on, its object beginning with the prefix where `first` is 0.
 */
let seal: (
  ~key: Uint8Array.t,
  ~header: Parcel.header,
  ~first: int,
  Uint8Array.t,
) => promise<result<written, unsealable>>

/** The master's version a journal's first object begins with, read before its key is derived. */
let begun: Uint8Array.t => result<float, unopened>

/** An object opened from segment `first` on, what its write sealed and the index of the next. */
let opened: (
  ~key: Uint8Array.t,
  ~header: Parcel.header,
  ~first: int,
  Uint8Array.t,
) => promise<result<(Uint8Array.t, int), unopened>>
