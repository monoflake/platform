/***
 * What the tests take of node, its test runner, strict assertions, files from the repository's root
 * and UTF-8.
 */
type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readFileSync: (url, @as("utf8") _) => string = "readFileSync"

@module("node:test") external test: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"

/** A path from the repository's root, this file lying at `code/substrate/host/tests/bindings/`. */
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
