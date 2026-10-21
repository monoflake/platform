/***
 * What serve takes of the web's APIs beyond ReScript's Stdlib, UTF-8, a URL's path and the Fetch
 * API.
 */
type encoder
type decoder
type decoderOptions = {fatal: bool, ignoreBOM: bool}
@new external makeEncoder: unit => encoder = "TextEncoder"
@new external makeDecoder: (string, decoderOptions) => decoder = "TextDecoder"
@send external encodeWith: (encoder, string) => Uint8Array.t = "encode"
@send external decodeWith: (decoder, Uint8Array.t) => string = "decode"

let encoder = makeEncoder()
// Fatal, so bytes that are not UTF-8 are refused rather than replaced.
let decoder = makeDecoder("utf-8", {fatal: true, ignoreBOM: false})

/** A string's UTF-8. */
let utf8 = text => encoder->encodeWith(text)

/** The text UTF-8 bytes spell, or none where they are not UTF-8. */
let fromUtf8 = bytes =>
  try Some(decoder->decodeWith(bytes)) catch {
  | JsExn(_) => None
  }

type url
@new external makeUrl: string => url = "URL"
@get external pathname: url => string = "pathname"

/** The path of an absolute URL, as the URL parser writes it. */
let pathOf = text => makeUrl(text)->pathname

type request
type headers
type response
type responseInit = {status: int, headers: dict<string>}

@get external requestUrl: request => string = "url"
@get external requestMethod: request => string = "method"
@get external requestHeaders: request => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"
@send external arrayBuffer: request => promise<ArrayBuffer.t> = "arrayBuffer"
@new external makeResponse: (Uint8Array.t, responseInit) => response = "Response"

/** A request's body, whole. */
let bodyOf = async request => Uint8Array.fromBuffer(await request->arrayBuffer)
