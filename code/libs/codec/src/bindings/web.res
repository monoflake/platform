/***
 * What the codec takes of the web's APIs beyond ReScript's Stdlib: UTF-8 by `TextEncoder` and
 * `TextDecoder`, and a typed array's `set` from another.
 */
type encoder
type decoder
type decoderOptions = {fatal: bool, ignoreBOM: bool}
@new external makeEncoder: unit => encoder = "TextEncoder"
@new external makeDecoder: (string, decoderOptions) => decoder = "TextDecoder"
@send external encodeWith: (encoder, string) => Uint8Array.t = "encode"
@send external decodeWith: (decoder, Uint8Array.t) => string = "decode"

/** Writes `source` into `target` from `offset`. */
@send external setFrom: (Uint8Array.t, Uint8Array.t, int) => unit = "set"

let encoder = makeEncoder()
// Fatal, so bytes that are not UTF-8 are refused rather than replaced; a byte order mark is text.
let decoder = makeDecoder("utf-8", {fatal: true, ignoreBOM: true})

/** A string's UTF-8. */
let utf8 = text => encoder->encodeWith(text)

/** The text UTF-8 bytes spell, or none where they are not UTF-8. */
let fromUtf8 = bytes =>
  try Some(decoder->decodeWith(bytes)) catch {
  | JsExn(_) => None
  }
