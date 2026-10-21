/***
 * What the runner's command takes of node, since it runs beside an implementation and never in
 * it: its arguments and exit code, and its files, the model's contracts found from the repository's
 * root.
 */
@module("node:process") external argv: array<string> = "argv"
type process
@module("node:process") external process: process = "default"
@set external setExitCode: (process, int) => unit = "exitCode"

@module("node:fs") external readFileSync: (string, @as("utf8") _) => string = "readFileSync"

type url
@new external urlIn: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readUrl: (url, @as("utf8") _) => string = "readFileSync"

/** A file from the repository's root, this one lying at `code/tools/runner/src/bindings/`. */
let fromRoot = path => readUrl(urlIn(`../../../../../${path}`, importMetaUrl))
