/***
 * What the tests take of node, its test runner, strict assertions, files, processes, an HTTP
 * server, and deploy's bundle, read from that tool as it was built.
 */
@module("node:test") external test: (string, unit => promise<unit>) => unit = "test"

@module("node:assert/strict")
external deepEqual: ('a, 'a, ~message: string=?) => unit = "deepStrictEqual"
@module("node:assert/strict") external ok: (bool, ~message: string=?) => unit = "ok"

type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external pathOf: url => string = "fileURLToPath"

/** A path from the repository's root, this file at `code/products/control/tests/bindings/`. */
let fromRoot = path => pathOf(urlIn(`../../../../../${path}`, importMetaUrl))

@module("node:process") external env: dict<string> = "env"
@module("node:fs") external exists: string => bool = "existsSync"
@module("node:fs") external readBytes: string => Uint8Array.t = "readFileSync"
@module("node:fs") external readText: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external mkdtemp: string => string = "mkdtempSync"
type removed = {recursive: bool, force: bool}
@module("node:fs") external rm: (string, removed) => unit = "rmSync"
type listed = {recursive: bool}
@module("node:fs") external list: (string, listed) => array<string> = "readdirSync"
type stats
@module("node:fs") external stat: string => stats = "statSync"
@send external isFile: stats => bool = "isFile"
@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:path") @variadic external join: array<string> => string = "join"

type spawned = {status: Nullable.t<int>, stdout: Nullable.t<string>, stderr: Nullable.t<string>}
type spawnOptions = {cwd?: string, env?: dict<string>, stdio: array<string>, encoding?: string}
@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawned = "spawnSync"

/** A program run to its end, what it wrote, or why it failed with what it wrote. */
let ran = (program, args, ~cwd=?, ~env=?) => {
  let done = spawnSync(
    program,
    args,
    {?cwd, ?env, stdio: ["ignore", "pipe", "pipe"], encoding: "utf8"},
  )
  let said = text => text->Nullable.toOption->Option.getOr("")->String.trim
  switch done.status->Nullable.toOption {
  | Some(0) => Ok(said(done.stdout))
  | _ => Error(`${program} failed, ${said(done.stderr)} ${said(done.stdout)}`->String.trim)
  }
}

type child
type stream
@module("node:child_process")
external spawn: (string, array<string>, spawnOptions) => child = "spawn"
@send external kill: (child, string) => bool = "kill"
@get external stdout: child => stream = "stdout"
@get external stderr: child => stream = "stderr"
@send external onText: (stream, @as("data") _, Uint8Array.t => unit) => unit = "on"
@send external onExit: (child, @as("exit") _, unit => unit) => unit = "once"

/** A child stopped, kept until it has exited. */
let stopped = child =>
  Promise.make((resolve, _) => {
    child->onExit(() => resolve())
    child->kill("SIGTERM")->ignore
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
@send external closeAll: server => unit = "closeAllConnections"

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

/** A server listening on a free port of the loopback address, and that port. */
let listening = handler =>
  Promise.make((resolve, _) => {
    let server = createServer(handler)
    server->listen(0, "127.0.0.1", () => resolve((server, (server->address).port)))
  })

let shut = server =>
  Promise.make((resolve, _) => {
    server->close(() => resolve())
    server->closeAll
  })

/** What deploy's bundle module gives, as `code/tools/deploy/src/bundle.resi` writes it. */
type bundleConfig
type bundled = {name: string, bytes: Uint8Array.t}
type bundle = {
  config: string => result<bundleConfig, string>,
  packed: (
    ~kinds: array<Envelope.Contracts.DeploymentKind.t>=?,
    ~ingress: array<Envelope.Contracts.AppIngress.t>=?,
    bundleConfig,
    array<bundled>,
  ) => result<Uint8Array.t, string>,
}

/** deploy's bundle, read from its compiled module once deploy is built. */
let bundle: unit => promise<
  bundle,
> = %raw(`() => import("../../../../tools/deploy/src/bundle.res.mjs")`)

/** How a request follows a redirect, as fetch reads it. */
@get external redirectOf: Web.request => string = "redirect"
