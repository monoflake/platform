/***
 * A sealed parcel kept as shards with parity rather than as whole copies, which row C21 asks of
 * RFC 13ixj and b8f35, together with whether the owner sees which: held here so that its place is
 * made, and implemented by `%todo("C21")` until the row is decided. The model's interface,
 * `docs/code.md`.
 */

/** A parcel cut into `data` shards and `parity` more, any `data` of them restoring it. */
let shards: (Uint8Array.t, ~data: int, ~parity: int) => array<Uint8Array.t>

/** A parcel restored from its shards, by their indices, those lost none, or none where fewer than
 * `data` are left. */
let restored: (array<option<Uint8Array.t>>, ~data: int, ~parity: int) => option<Uint8Array.t>
