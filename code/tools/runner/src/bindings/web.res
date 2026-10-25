/***
 * What the runner takes of the web's APIs beyond ReScript's Stdlib, UTF-8, base64url, bytes copied,
 * a timer, `fetch` and random bytes.
 */
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

type base64 = {alphabet: string, omitPadding: bool}
@send external toBase64: (Uint8Array.t, base64) => string = "toBase64"

/** Bytes in base64url, unpadded, as RFC fhg6w writes them. */
let base64url = bytes => bytes->toBase64({alphabet: "base64url", omitPadding: true})

@val external setTimeout: (unit => unit, int) => unit = "setTimeout"

/** A promise kept after so many milliseconds. */
let sleep = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms))

type request = {method: string, headers: dict<string>, body?: Uint8Array.t}
type response
type headers

@val external fetch: (string, request) => promise<response> = "fetch"
@get external status: response => int = "status"
@get external headers: response => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"
@send external arrayBuffer: response => promise<ArrayBuffer.t> = "arrayBuffer"

@val @scope("crypto") external fillRandom: Uint8Array.t => Uint8Array.t = "getRandomValues"

/** So many bytes from the system's secure random source. */
let random = length => fillRandom(Uint8Array.fromLength(length))

/** Bytes written into another array from an offset. */
@send external copyInto: (Uint8Array.t, Uint8Array.t, int) => unit = "set"

type url
@new external makeUrl: string => url = "URL"
@get external hostname: url => string = "hostname"

/** A URL's host as the WHATWG parser leaves it, or none where it refuses the text. */
let hostOf = text =>
  switch makeUrl(text) {
  | url => Some(url->hostname)
  | exception JsExn(_) => None
  }
