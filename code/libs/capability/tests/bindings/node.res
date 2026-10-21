/***
 * What the tests take of node: its test runner, its strict assertions, and its files, found from
 * the repository's root.
 */
type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readFileSync: (url, @as("utf8") _) => string = "readFileSync"

@module("node:test") external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"

/** A path from the repository's root, this file lying at `code/libs/capability/tests/bindings/`. */
let fromRoot = path => urlIn(`../../../../../${path}`, importMetaUrl)
