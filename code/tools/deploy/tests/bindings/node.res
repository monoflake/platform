/*** What the tests take of node, its test runner and strict assertions. */
@module("node:test") external test: (string, unit => unit) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"
@module("node:assert/strict") external ok: (bool, ~message: string=?) => unit = "ok"
@module("node:test") external testAsync: (string, unit => promise<unit>) => unit = "test"

/** A response as a fetch gives it, its status and its body. */
@new external response: (string, {"status": int}) => Web.response = "Response"
