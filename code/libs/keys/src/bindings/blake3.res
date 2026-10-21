/***
 * What keys takes of `@noble/hashes`: BLAKE3, unkeyed, keyed by 32 bytes, or deriving a key under
 * a context's UTF-8, each to `dkLen` bytes of its extended output, 32 where none is given.
 */
type options = {dkLen?: int, key?: Uint8Array.t, context?: Uint8Array.t}

@module("@noble/hashes/blake3.js") external hash: Uint8Array.t => Uint8Array.t = "blake3"
@module("@noble/hashes/blake3.js")
external hashWith: (Uint8Array.t, options) => Uint8Array.t = "blake3"
