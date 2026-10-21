/***
 * A parcel, RFC b8f35: exactly 16 MiB, its pieces packed whole into it and zeros after, sealed in
 * segments by AES-256-GCM under a key of its own, `Keys.Derive.parcel` from its seed, so
 * its size alone says it is whole. Sealing is WebCrypto's on every runtime, so it answers a promise.
 * The model's interface, `docs/code.md`.
 *
 * Its header is 41 bytes: `MOFL`; the revision, 1; the encryption master's version, 4 bytes
 * big-endian, at least 1; and the seed, 32 bytes. Then 256 segments follow, 255 of 65,536 bytes and
 * the last of 61,399, each sealed with its 16-byte tag: segment `i` under the nonce `8 zero bytes ||
 * u32_be(i)` and the associated data `header || u32_be(i) || final`, `final` 0x01 for segment 255
 * alone and 0x00 for every other, rebuilt as it is read and never written. Revision 2, sealed by
 * ChaCha20-Poly1305, is defined and refused as reserved; any other is refused.
 */

/** 16,777,216 bytes, a parcel whole. */
let size: int

/** 16,773,079 bytes, what a parcel holds of pieces. */
let capacity: int

/** What a parcel's header says beside its magic and revision. */
type header = {master: float, seed: Uint8Array.t}

/** Why a parcel was not sealed, the first of these: a key not of 32 bytes, a master's version not
 * an integer of 1 to 2^32 - 1, a seed not of 32 bytes, or more than `capacity` bytes to seal. */
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
 * Where a piece of `length` bytes goes in a parcel holding `used` already: at `used`, or none where
 * it would not fit, a piece never spanning two parcels, or where either is below 0.
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

/** A parcel opened, whole: its header and its `capacity` bytes, zeros after its pieces. */
let opened: (~key: Uint8Array.t, Uint8Array.t) => promise<result<(header, Uint8Array.t), unopened>>
