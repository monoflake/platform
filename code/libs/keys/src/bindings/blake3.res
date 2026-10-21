/***
 * What keys takes of `@noble/hashes`, BLAKE3 unkeyed, keyed or deriving under a context, to `dkLen`
 * bytes.
 */
type options = {dkLen?: int, key?: Uint8Array.t, context?: Uint8Array.t}

@module("@noble/hashes/blake3.js") external hash: Uint8Array.t => Uint8Array.t = "blake3"
@module("@noble/hashes/blake3.js")
external hashWith: (Uint8Array.t, options) => Uint8Array.t = "blake3"
