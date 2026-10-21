/***
 * What the tests take of node: its test runner, its strict assertions, its files, found from the
 * repository's root, and an HTTP server an end-to-end test answers by.
 */
type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readFileSync: (url, @as("utf8") _) => string = "readFileSync"

type entry
type listing = {withFileTypes: bool}
@module("node:fs") external entries: (url, listing) => array<entry> = "readdirSync"
@get external entryName: entry => string = "name"
@send external isDirectory: entry => bool = "isDirectory"

@module("node:test") external test: (string, unit => unit) => unit = "test"
@module("node:test") external testAsync: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"
@module("node:assert/strict") external ok: (bool, ~message: string=?) => unit = "ok"

/** A path from the repository's root, this file lying at `code/tools/runner/tests/bindings/`. */
let fromRoot = path => urlIn(`../../../../../${path}`, importMetaUrl)

/** A path from the block's own directory. */
let fromBlock = path => urlIn(`../../${path}`, importMetaUrl)

/** Every `.json` beneath a directory of the repository, by its path from the root. */
let rec files = path =>
  entries(fromRoot(`${path}/`), {withFileTypes: true})->Array.flatMap(e => {
    let inner = `${path}/${e->entryName}`
    e->isDirectory ? files(inner) : inner->String.endsWith(".json") ? [inner] : []
  })

type request
type response
type server
type address = {port: int}

@get external method: request => string = "method"
@get external path: request => string = "url"
@get external requestHeaders: request => dict<string> = "headers"
@send external on: (request, string, 'a => unit) => unit = "on"

@send external writeHead: (response, int, dict<string>) => unit = "writeHead"
@send external end: (response, Uint8Array.t) => unit = "end"

@module("node:http")
external createServer: ((request, response) => unit) => server = "createServer"
@send external listen: (server, int, string, unit => unit) => unit = "listen"
@send external address: server => address = "address"
@send external close: (server, unit => unit) => unit = "close"

type buffer
@module("node:buffer") @scope("Buffer") external concat: array<buffer> => buffer = "concat"
@new external bytesOf: buffer => Uint8Array.t = "Uint8Array"

/** A request's body, whole. */
let body = request =>
  Promise.make((resolve, _) => {
    let chunks = []
    request->on("data", chunk => chunks->Array.push(chunk))
    request->on("end", () => resolve(bytesOf(concat(chunks))))
  })

let stop = server => Promise.make((resolve, _) => server->close(() => resolve()))
