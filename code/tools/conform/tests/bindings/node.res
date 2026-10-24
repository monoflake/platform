/*** What the tests take of node, its test runner, strict assertions
and a directory of their own. */
@module("node:test") external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"
@module("node:assert/strict") external ok: (bool, ~message: string=?) => unit = "ok"

@module("node:fs") external readText: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external mkdtemp: string => string = "mkdtempSync"
type removed = {recursive: bool, force: bool}
@module("node:fs") external rm: (string, removed) => unit = "rmSync"
@module("node:os") external tmpdir: unit => string = "tmpdir"
