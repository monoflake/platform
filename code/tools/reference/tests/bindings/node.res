@module("node:test") external test: (string, unit => promise<unit>) => unit = "test"
@module("node:assert/strict") external equal: ('a, 'a) => unit = "deepStrictEqual"
@module("node:assert/strict") external ok: bool => unit = "ok"
type init = {method: string, body?: string}
@new external request: (string, init) => Web.request = "Request"
@get external status: Web.response => int = "status"
@send external text: Web.response => promise<string> = "text"
@module("node:fs") external readFileSync: (string, string) => string = "readFileSync"
type encoder
@new external textEncoder: unit => encoder = "TextEncoder"
@send external encode: (encoder, string) => Uint8Array.t = "encode"
type decoder
@new external textDecoder: unit => decoder = "TextDecoder"
@send external decode: (decoder, Uint8Array.t) => string = "decode"
