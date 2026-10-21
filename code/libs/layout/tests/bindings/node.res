/***
 * What the tests take of node, its test runner, strict assertions and files, and of the web
 * `TextEncoder`.
 */
type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readFileSync: (url, @as("utf8") _) => string = "readFileSync"

@module("node:test") external test: (string, unit => unit) => unit = "test"
@module("node:test") external testAsync: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"

/** A path from the repository's root, this file lying at `code/libs/layout/tests/bindings/`. */
let fromRoot = path => urlIn(`../../../../../${path}`, importMetaUrl)

type encoder
@new external makeEncoder: unit => encoder = "TextEncoder"
@send external encodeWith: (encoder, string) => Uint8Array.t = "encode"

let encoder = makeEncoder()

/** A string's UTF-8. */
let utf8 = text => encoder->encodeWith(text)
