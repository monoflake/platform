/***
 * What the control takes of the web's APIs, requests and responses, a URL's parts, UTF-8, SHA-256
 * and random bytes, alike on a Worker and in node.
 */
type request
type response
type headers
/** A body as a stream, passed on unread. */
type body

@get external url: request => string = "url"
@get external method_: request => string = "method"
@get external requestHeaders: request => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"
@send external setHeader: (headers, string, string) => unit = "set"
@send external requestBytes: request => promise<ArrayBuffer.t> = "arrayBuffer"
@get external requestBody: request => Nullable.t<body> = "body"

/** A request whole. */
let bytesOf = async request => Uint8Array.fromBuffer(await request->requestBytes)

type requestInit = {method: string, headers: dict<string>, body?: Uint8Array.t}
@new external request: (string, requestInit) => request = "Request"
/** A request as it came, sent to another URL. */
@new external resent: (string, request) => request = "Request"

type responseInit = {status: int, headers: dict<string>}
@new external response: (Uint8Array.t, responseInit) => response = "Response"
@new external streamed: (body, responseInit) => response = "Response"
@get external status: response => int = "status"
@get external responseHeaders: response => headers = "headers"
@send external text: response => promise<string> = "text"
@send external responseBuffer: response => promise<ArrayBuffer.t> = "arrayBuffer"

/** A response's body whole. */
let responseBytes = async response => Uint8Array.fromBuffer(await response->responseBuffer)

/** What sends a request and gives its response, a global fetch or a binding's. */
type fetch = request => promise<response>
@val external fetch: fetch = "fetch"
type fetcher
@send external fetchThrough: (fetcher, request) => promise<response> = "fetch"

type parts
@new external parts: string => parts = "URL"
@get external origin: parts => string = "origin"
@get external pathname: parts => string = "pathname"
@get external search: parts => string = "search"

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
let fromUtf8 = bytes => decoder->decodeWith(bytes)

/** A text written as a response, of the type given. */
let answered = (~status, ~contentType="text/plain; charset=utf-8", body) =>
  response(utf8(body), {status, headers: dict{"content-type": contentType}})

@val @scope(("crypto", "subtle"))
external digestOf: (string, Uint8Array.t) => promise<ArrayBuffer.t> = "digest"

/** Bytes' SHA-256. */
let sha256 = async bytes => Uint8Array.fromBuffer(await digestOf("SHA-256", bytes))

@val @scope("crypto") external fillRandom: Uint8Array.t => Uint8Array.t = "getRandomValues"

/** So many random bytes. */
let random = length => fillRandom(Uint8Array.fromLength(length))

@val external setTimeout: (unit => unit, int) => unit = "setTimeout"

/** A promise kept after so many milliseconds. */
let sleep = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms))
