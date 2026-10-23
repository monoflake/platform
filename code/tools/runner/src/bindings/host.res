/***
 * What the runner's command takes of node, its arguments, exit code, stdin and files from the
 * repository's root.
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
