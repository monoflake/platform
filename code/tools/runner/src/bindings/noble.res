/***
 * What the runner takes of `@noble/hashes` and `@noble/curves`, BLAKE3 to a length, SHA-256 and
 * Ed25519, RFC p8e8k.
 */
type options = {dkLen: int}

@module("@noble/hashes/blake3.js")
external blake3: (Uint8Array.t, options) => Uint8Array.t = "blake3"

type keys = {secretKey: Uint8Array.t, publicKey: Uint8Array.t}

@module("@noble/curves/ed25519.js") @scope("ed25519")
external keygen: unit => keys = "keygen"

@module("@noble/curves/ed25519.js") @scope("ed25519")
external sign: (Uint8Array.t, Uint8Array.t) => Uint8Array.t = "sign"

@module("@noble/hashes/sha2.js")
external sha256: Uint8Array.t => Uint8Array.t = "sha256"
