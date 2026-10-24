/***
 * What the tool takes of node, its arguments, exit code and signals, files from the repository's
 * root and a directory of its own, processes run to their end or left running, a free port, `fetch`
 * and a timer.
 */
@module("node:process") external argv: array<string> = "argv"
@module("node:process") external execPath: string = "execPath"
type process
@module("node:process") external process: process = "default"
@set external setExitCode: (process, int) => unit = "exitCode"
@send external onSignal: (process, string, unit => unit) => unit = "on"
@send external exit: (process, int) => unit = "exit"

type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external pathOf: url => string = "fileURLToPath"

/** A path from the repository's root, this file lying at `code/tools/conform/src/bindings/`. */
let fromRoot = path => pathOf(urlIn(`../../../../../${path}`, importMetaUrl))

@module("node:fs") external readText: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external list: string => array<string> = "readdirSync"
@module("node:fs") external readBytes: string => Uint8Array.t = "readFileSync"
@module("node:fs") external writeText: (string, string) => unit = "writeFileSync"
@module("node:fs") external mkdtemp: string => string = "mkdtempSync"
type removed = {recursive: bool, force: bool}
@module("node:fs") external rm: (string, removed) => unit = "rmSync"
type made = {recursive: bool}
@module("node:fs") external mkdir: (string, made) => unit = "mkdirSync"
@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:os") external homedir: unit => string = "homedir"

type spawned = {status: Nullable.t<int>, stdout: Nullable.t<string>, stderr: Nullable.t<string>}
type spawnOptions = {input?: string, stdio: array<string>, encoding: string, cwd?: string}
@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawned = "spawnSync"
type bytesOptions = {input: Uint8Array.t, stdio: array<string>, encoding: string}
@module("node:child_process")
external spawnSyncBytes: (string, array<string>, bytesOptions) => spawned = "spawnSync"

type child
type childOptions = {stdio: array<string>, cwd?: string}
@module("node:child_process")
external spawn: (string, array<string>, childOptions) => child = "spawn"
@send
external onExit: (child, @as("exit") _, (Nullable.t<int>, Nullable.t<string>) => unit) => unit =
  "on"
@send external kill: child => bool = "kill"
type writable
@get external stdin: child => writable = "stdin"
@send external endWith: (writable, string) => unit = "end"

/** A child's exit code once it ends, 1 where a signal ended it. */
let ended = child =>
  Promise.make((resolve, _) =>
    child->onExit((code, _) => resolve(code->Nullable.toOption->Option.getOr(1)))
  )

type server
type address = {port: int}
@module("node:net") external createServer: unit => server = "createServer"
@send external listen: (server, int, string, unit => unit) => unit = "listen"
@send external address: server => address = "address"
@send external close: (server, unit => unit) => unit = "close"

/** A port of localhost nothing listens on, as the system gives one and takes it back. */
let freePort = () =>
  Promise.make((resolve, _) => {
    let server = createServer()
    server->listen(0, "127.0.0.1", () => {
      let port = (server->address).port
      server->close(() => resolve(port))
    })
  })

type response
type signal
type init = {signal: signal}
@val @scope("AbortSignal") external timeout: int => signal = "timeout"
@val external fetch: (string, init) => promise<response> = "fetch"

/** A URL fetched, given up on after so many milliseconds. */
let fetchWithin = (url, ms) => fetch(url, {signal: timeout(ms)})
@get external status: response => int = "status"
@send external text: response => promise<string> = "text"

@val external setTimeout: (unit => unit, int) => unit = "setTimeout"

/** A promise kept after so many milliseconds. */
let sleep = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms))
