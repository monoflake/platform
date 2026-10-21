/***
 * A sealed parcel kept as shards with parity, which row C21 asks, implemented by `%todo("C21")`
 * until it is decided. The model's interface, `docs/code.md`.
 */

/** A parcel cut into `data` shards and `parity` more, any `data` of them restoring it. */
let shards: (Uint8Array.t, ~data: int, ~parity: int) => array<Uint8Array.t>

/** A parcel restored from its shards, by their indices, those lost none, or none where fewer than
 * `data` are left. */
let restored: (array<option<Uint8Array.t>>, ~data: int, ~parity: int) => option<Uint8Array.t>
