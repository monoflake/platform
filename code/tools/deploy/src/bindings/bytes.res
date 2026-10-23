/*** What the tool takes of the web's APIs for bytes, UTF-8 and one array copied into another. */
type encoder
@new external makeEncoder: unit => encoder = "TextEncoder"
@send external encodeWith: (encoder, string) => Uint8Array.t = "encode"

let encoder = makeEncoder()

/** A string's UTF-8. */
let utf8 = text => encoder->encodeWith(text)

type decoder
@new external makeDecoder: unit => decoder = "TextDecoder"
@send external decodeWith: (decoder, Uint8Array.t) => string = "decode"

let decoder = makeDecoder()

/** UTF-8 read as text. */
let text = bytes => decoder->decodeWith(bytes)

/** Bytes written into another array from an offset. */
@send external copyInto: (Uint8Array.t, Uint8Array.t, int) => unit = "set"
