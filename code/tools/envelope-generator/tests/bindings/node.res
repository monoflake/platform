/***
 * What the tests take of node, its test runner, strict assertions and files from the repository's
 * root.
 */
type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readFileSync: (url, @as("utf8") _) => string = "readFileSync"

@module("node:test") external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"
@module("node:assert/strict") external ok: (bool, ~message: string=?) => unit = "ok"

/**
 * A path from the repository's root, this file lying in
 * `code/tools/envelope-generator/tests/bindings/`.
 */
let fromRoot = path => urlIn(`../../../../../${path}`, importMetaUrl)
