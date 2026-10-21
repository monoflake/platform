/***
 * A parcel, exactly 16 MiB of pieces sealed in segments by AES-256-GCM under its own key, as RFC
 * b8f35 lays it out. The model's interface, `docs/code.md`.
 */

/** 16,777,216 bytes, a parcel whole. */
let size: int

/** 16,773,079 bytes, what a parcel holds of pieces. */
let capacity: int

/** What a parcel's header says beside its magic and revision. */
type header = {master: float, seed: Uint8Array.t}

/**
 * Why a parcel was not sealed, the first of a bad key, master's version or seed, or too much to
 * seal.
 */
type unsealable = Key | Master | Seed | Overfull

/** Why bytes were not opened as a parcel, the first of these, in their order; the key is asked
 * only of `opened`, and the segments in their order. */
type unopened =
  /** Not `size` bytes. */
  | Size
  /** Not begun by `MOFL`. */
  | Magic
  /** Revision 2, defined and not built. */
  | Reserved
  /** A revision undefined. */
  | Revision(int)
  /** A master's version of 0. */
  | Master
  /** A key not of 32 bytes. */
  | Key
  /** A segment whose tag does not hold, by its index. */
  | Tag(int)

/**
 * Where a piece of `length` bytes goes in a parcel holding `used`, at `used`, or none where it
 * would not fit.
 */
let fits: (~used: int, ~length: int) => option<int>

/** The parcel holding the pieces joined, `capacity` bytes at most, zeros after them, sealed. */
let seal: (
  ~key: Uint8Array.t,
  ~header: header,
  Uint8Array.t,
) => promise<result<Uint8Array.t, unsealable>>

/** A parcel's header, read before its key is derived from its seed. */
let header: Uint8Array.t => result<header, unopened>

/** A parcel opened whole, its header and its `capacity` bytes, zeros after its pieces. */
let opened: (~key: Uint8Array.t, Uint8Array.t) => promise<result<(header, Uint8Array.t), unopened>>
