/***
 * What the tool takes of node, its arguments, environment and exit code, files, processes, a timer
 * and SHA-256.
 */
@module("node:process") external argv: array<string> = "argv"
@module("node:process") external env: dict<string> = "env"
type process
@module("node:process") external process: process = "default"
@set external setExitCode: (process, int) => unit = "exitCode"

type spawned = {status: Nullable.t<int>, stdout: Nullable.t<string>, stderr: Nullable.t<string>}
type spawnOptions = {
  cwd?: string,
  input?: string,
  env?: dict<string>,
  stdio: array<string>,
  encoding: string,
}
@module("node:child_process")
external spawnSync: (string, array<string>, spawnOptions) => spawned = "spawnSync"

@module("node:fs") external exists: string => bool = "existsSync"
@module("node:fs") external readBytes: string => Uint8Array.t = "readFileSync"
@module("node:fs") external readText: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external writeBytes: (string, Uint8Array.t) => unit = "writeFileSync"
@module("node:fs") external makeTemporary: string => string = "mkdtempSync"

type removing = {recursive: bool, force: bool}
@module("node:fs") external remove: (string, removing) => unit = "rmSync"

type listing = {recursive: bool}
@module("node:fs") external list: (string, listing) => array<string> = "readdirSync"
type stats
@module("node:fs") external stat: string => stats = "statSync"
@send external isFile: stats => bool = "isFile"

@module("node:os") external temporary: unit => string = "tmpdir"
@module("node:path") external absolute: string => string = "resolve"
@module("node:path") @variadic external join: array<string> => string = "join"

type digest
@module("node:crypto") external createHash: string => digest = "createHash"
@send external update: (digest, Uint8Array.t) => digest = "update"
@send external finish: digest => Uint8Array.t = "digest"

/** A content's SHA-256, as the container kind holds an artifact to it. */
let sha256 = bytes => createHash("sha256")->update(bytes)->finish

@val @scope("crypto") external fillRandom: Uint8Array.t => Uint8Array.t = "getRandomValues"

@val external setTimeout: (unit => unit, int) => unit = "setTimeout"

/** A promise kept after so many milliseconds. */
let sleep = ms => Promise.make((resolve, _) => setTimeout(() => resolve(), ms))
