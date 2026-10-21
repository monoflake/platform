/*** What the tests take of `@noble/hashes`, unkeyed BLAKE3 to `dkLen` bytes, 32 unless given. */
type options = {dkLen?: int}

@module("@noble/hashes/blake3.js") external hash: Uint8Array.t => Uint8Array.t = "blake3"
@module("@noble/hashes/blake3.js")
external hashWith: (Uint8Array.t, options) => Uint8Array.t = "blake3"
