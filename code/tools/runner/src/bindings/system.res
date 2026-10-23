/***
 * What the runner's commands take of node, their arguments, exit code, stdin, files from the
 * repository's root and of their own, and programs run.
 */
@module("node:process") external argv: array<string> = "argv"
type process
@module("node:process") external process: process = "default"
@set external setExitCode: (process, int) => unit = "exitCode"

@module("node:fs") external readFileSync: (string, @as("utf8") _) => string = "readFileSync"

type stream
@module("node:process") external stdin: stream = "stdin"
@send external setEncoding: (stream, @as("utf8") _) => unit = "setEncoding"
@send external onData: (stream, @as("data") _, string => unit) => unit = "on"
@send external onEnd: (stream, @as("end") _, unit => unit) => unit = "on"
@send external onError: (stream, @as("error") _, JsExn.t => unit) => unit = "on"

/** What stdin holds, read to its end as a pipe gives it. */
let readStdin = () =>
  Promise.make((resolve, _) => {
    let chunks = []
    stdin->setEncoding
    stdin->onData(chunk => chunks->Array.push(chunk))
    stdin->onEnd(() => resolve(Ok(chunks->Array.join(""))))
    stdin->onError(e => resolve(Error(e->JsExn.message->Option.getOr("not read"))))
  })

type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readUrl: (url, @as("utf8") _) => string = "readFileSync"

/** A file from the repository's root, this one lying at `code/tools/runner/src/bindings/`. */
let fromRoot = path => readUrl(urlIn(`../../../../../${path}`, importMetaUrl))

@module("node:url") external pathOf: url => string = "fileURLToPath"

/** A path from the repository's root, as `fromRoot` reads it. */
let rootPath = path => pathOf(urlIn(`../../../../../${path}`, importMetaUrl))

@module("node:fs") external list: string => array<string> = "readdirSync"
@module("node:fs") external exists: string => bool = "existsSync"
@module("node:fs") external readBytes: string => Uint8Array.t = "readFileSync"
@module("node:fs") external writeBytes: (string, Uint8Array.t) => unit = "writeFileSync"
@module("node:fs") external writeText: (string, string) => unit = "writeFileSync"
type made = {recursive: bool}
@module("node:fs") external mkdir: (string, made) => unit = "mkdirSync"
@module("node:fs") external mkdtemp: string => string = "mkdtempSync"
type removed = {recursive: bool, force: bool}
@module("node:fs") external rm: (string, removed) => unit = "rmSync"
@module("node:os") external tmpdir: unit => string = "tmpdir"

type spawned = {status: Nullable.t<int>, stdout: Nullable.t<string>, stderr: Nullable.t<string>}
type spawnOptions = {stdio: array<string>, encoding: string}
@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawned = "spawnSync"

/** A program run to its end, what it wrote to stdout, or why it failed with what it wrote. */
let ran = (program, args) => {
  let done = spawnSync(program, args, {stdio: ["ignore", "pipe", "pipe"], encoding: "utf8"})
  let said = text => text->Nullable.toOption->Option.getOr("")
  switch done.status->Nullable.toOption {
  | Some(0) => Ok(said(done.stdout))
  | Some(_) | None => Error(`${program} failed, ${said(done.stderr)->String.trim}`)
  }
}

type child
type pipe
type childOptions = {stdio: array<string>}
@module("node:child_process")
external spawn: (string, array<string>, childOptions) => child = "spawn"
@get external childStdin: child => pipe = "stdin"
@get external childStdout: child => pipe = "stdout"
@get external childStderr: child => pipe = "stderr"
@send external endWith: (pipe, Uint8Array.t) => unit = "end"
@send external onChunk: (pipe, @as("data") _, Uint8Array.t => unit) => unit = "on"
@send external onClose: (child, @as("close") _, Nullable.t<int> => unit) => unit = "on"
@send external onSpawnError: (child, @as("error") _, JsExn.t => unit) => unit = "on"

type buffer
@module("node:buffer") @scope("Buffer") external concat: array<Uint8Array.t> => buffer = "concat"
@new external bytesOf: buffer => Uint8Array.t = "Uint8Array"

/** A program given its stdin, its exit code once it closes, and all it wrote to each stream. */
let piped = (program, args, input) =>
  Promise.make((resolve, _) => {
    let out = []
    let err = []
    let child = spawn(program, args, {stdio: ["pipe", "pipe", "pipe"]})
    child->childStdout->onChunk(chunk => out->Array.push(chunk))
    child->childStderr->onChunk(chunk => err->Array.push(chunk))
    child->onSpawnError(e => resolve(Error(e->JsExn.message->Option.getOr("not started"))))
    child->onClose(code =>
      resolve(
        Ok((code->Nullable.toOption->Option.getOr(1), bytesOf(concat(out)), bytesOf(concat(err)))),
      )
    )
    child->childStdin->endWith(input)
  })

@module("node:path") external resolve: string => string = "resolve"

/** A path made absolute from the working directory. */
let absolute = path => resolve(path)
