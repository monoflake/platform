/***
 * What the tests take of node: its test runner, its strict assertions, its files, found from the
 * repository's root, and its global `Request` and `Response`, as a Worker gives them.
 */
type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readFileSync: (url, @as("utf8") _) => string = "readFileSync"

@module("node:test") external test: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"
@module("node:assert/strict") external ok: (bool, ~message: string=?) => unit = "ok"

/** A path from the repository's root, this file lying at `code/libs/serve/tests/bindings/`. */
let fromRoot = path => urlIn(`../../../../../${path}`, importMetaUrl)

type encoder
type decoder
@new external makeEncoder: unit => encoder = "TextEncoder"
@new external makeDecoder: unit => decoder = "TextDecoder"
@send external encodeWith: (encoder, string) => Uint8Array.t = "encode"
@send external decodeWith: (decoder, Uint8Array.t) => string = "decode"

/** A string's UTF-8. */
let utf8 = text => makeEncoder()->encodeWith(text)

/** The text UTF-8 bytes spell. */
let text = bytes => makeDecoder()->decodeWith(bytes)

type requestInit = {method: string, headers: dict<string>, body?: Uint8Array.t}
type headers
@new external jsRequest: (string, requestInit) => Fetch.jsRequest = "Request"
@get external status: Fetch.jsResponse => int = "status"
@get external headers: Fetch.jsResponse => headers = "headers"
@send external header: (headers, string) => Nullable.t<string> = "get"
@send external arrayBuffer: Fetch.jsResponse => promise<ArrayBuffer.t> = "arrayBuffer"

/** A response's body, whole. */
let bodyOf = async response => Uint8Array.fromBuffer(await response->arrayBuffer)
