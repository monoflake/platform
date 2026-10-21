/***
 * What the runner takes of `@noble/hashes` and `@noble/curves`: BLAKE3 read out to a length, for
 * `$bytes` and a `kid`, and Ed25519's keys and signatures, for the chain a run makes, RFC p8e8k.
 */
type options = {dkLen: int}

@module("@noble/hashes/blake3.js")
external blake3: (Uint8Array.t, options) => Uint8Array.t = "blake3"

type keys = {secretKey: Uint8Array.t, publicKey: Uint8Array.t}

@module("@noble/curves/ed25519.js") @scope("ed25519")
external keygen: unit => keys = "keygen"

@module("@noble/curves/ed25519.js") @scope("ed25519")
external sign: (Uint8Array.t, Uint8Array.t) => Uint8Array.t = "sign"
