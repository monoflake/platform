/***
 * What the tests take of `@noble/hashes`: BLAKE3, unkeyed, to `dkLen` bytes of its extended output,
 * 32 where none is given, which makes the samples' content and holds their large results.
 */
type options = {dkLen?: int}

@module("@noble/hashes/blake3.js") external hash: Uint8Array.t => Uint8Array.t = "blake3"
@module("@noble/hashes/blake3.js")
external hashWith: (Uint8Array.t, options) => Uint8Array.t = "blake3"
