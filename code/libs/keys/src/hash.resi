/***
 * How each layer's record is named, RFC b8f35, by BLAKE3 in one of two modes, 32 bytes: what is
 * plaintext keyed by its scope's salt, since anyone holding the content could otherwise compute
 * its address; what is sealed unkeyed, so a parcel is checked and repaired with neither the salt nor
 * the key. The model's interface, `docs/code.md`.
 */

/** A content's or a piece's id: BLAKE3 keyed by the scope's salt, of 32 bytes. */
let keyed: (~salt: Uint8Array.t, Uint8Array.t) => result<Uint8Array.t, Derive.refused>

/** A sealed parcel's or a stored block's id: BLAKE3 unkeyed. */
let plain: Uint8Array.t => Uint8Array.t
