/***
 * What is derived from the masters and a scope by BLAKE3's `derive_key` under each `Context`, RFC
 * b8f35. The model's interface, `docs/code.md`.
 */

/**
 * Why a part was not derived from, by its label's name, the first of a wrong length or a number
 * outside its range.
 */
type refused =
  | Length({part: string, length: int})
  | Range({part: string})

/**
 * BLAKE3's `derive_key` under the context over the material, `length` bytes of its output, 32
 * unless given.
 */
let derive: (Context.t, Uint8Array.t, ~length: int=?) => Uint8Array.t

/** A scope's salt, from the salt master and the scope's id, an integer of 0 to 2^32 - 1. */
let salt: (~master: Uint8Array.t, ~scope: float) => result<Uint8Array.t, refused>

/** A scope's key, from the encryption master of a version and the scope's id. */
let key: (~master: Uint8Array.t, ~scope: float) => result<Uint8Array.t, refused>

/** A journal's key, from its scope's key and its seed. */
let journal: (~key: Uint8Array.t, ~seed: Uint8Array.t) => result<Uint8Array.t, refused>

/** A parcel's key, from its scope's key and its seed, its journal's or drawn at random. */
let parcel: (~key: Uint8Array.t, ~seed: Uint8Array.t) => result<Uint8Array.t, refused>

/** FastCDC's gear table from a scope's salt, the first 2,048 bytes of the extended output. */
let gear: (~salt: Uint8Array.t) => result<Uint8Array.t, refused>

/**
 * A store's score for a parcel at `k`, the first 8 bytes of the output as rendezvous reads them,
 * from the parcel's id, the store's and `k`.
 */
let score: (~parcel: Uint8Array.t, ~store: float, ~k: int) => result<Uint8Array.t, refused>
