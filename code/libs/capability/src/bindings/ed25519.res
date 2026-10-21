/***
 * What capability takes of `@noble/curves`, Ed25519 verified strictly by RFC 8032 and never
 * ZIP-215's encodings, RFC b8f35.
 */
type options = {zip215: bool}

@module("@noble/curves/ed25519.js") @scope("ed25519")
external verifyWith: (Uint8Array.t, Uint8Array.t, Uint8Array.t, options) => bool = "verify"

/**
 * Whether `key` verifies `signature` over `message`, never for a key or signature of the wrong
 * length.
 */
let verify = (~signature, ~message, ~key) =>
  try verifyWith(signature, message, key, {zip215: false}) catch {
  | JsExn(_) => false
  }
