/***
 * How each layer's record is named by BLAKE3, plaintext keyed by its scope's salt and sealed bytes
 * unkeyed, RFC b8f35. The model's interface, `docs/code.md`.
 */

/** A content's or a piece's id, BLAKE3 keyed by the scope's salt, 32 bytes. */
let keyed: (~salt: Uint8Array.t, Uint8Array.t) => result<Uint8Array.t, Derive.refused>

/** A sealed parcel's or a stored block's id, BLAKE3 unkeyed. */
let plain: Uint8Array.t => Uint8Array.t
