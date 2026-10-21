/***
 * What keys takes of the web's APIs beyond ReScript's Stdlib, `TextEncoder` and a typed array's
 * `set`.
 */
type encoder
@new external makeEncoder: unit => encoder = "TextEncoder"
@send external encodeWith: (encoder, string) => Uint8Array.t = "encode"

/** Writes `source` into `target` from `offset`. */
@send external setFrom: (Uint8Array.t, Uint8Array.t, int) => unit = "set"

let encoder = makeEncoder()

/** A string's UTF-8. */
let utf8 = text => encoder->encodeWith(text)
