/***
 * What is derived from the masters and a scope, RFC b8f35, each BLAKE3's `derive_key` under its
 * context, `Context`, over the parts named, joined in the order named: a master, a key and a seed of
 * 32 bytes, a scope's or a store's id as 4 bytes big-endian, as a derivation reads 8 hex digits. The
 * model's interface, `docs/code.md`.
 */

/** Why a part was not derived from, by its name as each function's label names it, the first in
 * their order: bytes of another length than it must have, or a number outside its range. */
type refused =
  | Length({part: string, length: int})
  | Range({part: string})

/** BLAKE3's `derive_key` under the context, over the material: `length` bytes of its extended
 * output, 32 where none is given. */
let derive: (Context.t, Uint8Array.t, ~length: int=?) => Uint8Array.t

/** A scope's salt, from the salt master and the scope's id, an integer of 0 to 2^32 - 1. */
let salt: (~master: Uint8Array.t, ~scope: float) => result<Uint8Array.t, refused>

/** A scope's key, from the encryption master of a version and the scope's id. */
let key: (~master: Uint8Array.t, ~scope: float) => result<Uint8Array.t, refused>

/** A journal's key, from its scope's key and its seed. */
let journal: (~key: Uint8Array.t, ~seed: Uint8Array.t) => result<Uint8Array.t, refused>

/** A parcel's key, from its scope's key and its seed, its journal's or drawn at random. */
let parcel: (~key: Uint8Array.t, ~seed: Uint8Array.t) => result<Uint8Array.t, refused>

/** FastCDC's gear table, from a scope's salt: the first 2,048 bytes of the extended output. */
let gear: (~salt: Uint8Array.t) => result<Uint8Array.t, refused>

/**
 * A store's score for a parcel at `k`, from the parcel's id, the store's id, an integer of 0 to
 * 2^32 - 1, and `k`, one byte, 0 to 255: the first 8 bytes of the output, as rendezvous reads them.
 */
let score: (~parcel: Uint8Array.t, ~store: float, ~k: int) => result<Uint8Array.t, refused>
