@module("node:test") external testAsync: (string, unit => promise<unit>) => unit = "test"
@module("node:assert/strict") external deepEqual: ('a, 'a) => unit = "deepEqual"

type requestInit = {method: string, headers: dict<string>, body?: string}
@new external request: (string, requestInit) => Worker.request = "Request"
@get external url: Worker.request => string = "url"
@get external method_: Worker.request => string = "method"
@get external headers: Worker.request => Web.headers = "headers"
@send external requestText: Worker.request => promise<string> = "text"
@get external status: Worker.response => int = "status"
@send external text: Worker.response => promise<string> = "text"

type fetch = Worker.request => promise<Worker.response>
@val @scope("globalThis") external currentFetch: fetch = "fetch"
let setFetch: fetch => unit = %raw(`value => { globalThis.fetch = value; }`)

@new external response: (string, Web.responseInit) => Worker.response = "Response"

let fail: unit => unit = %raw(`() => { throw new Error("entry unavailable"); }`)
