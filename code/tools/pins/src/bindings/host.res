/***
 * What the tool takes of node, since it runs while the platform is updated and never in it: its
 * arguments and exit, its files, the registry fetched, a download hashed, and git run as a child.
 */
@module("node:process") external argv: array<string> = "argv"
@module("node:process") external exit: int => unit = "exit"

@module("node:fs") external readFileSync: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"

type response
@val external fetch: string => promise<response> = "fetch"
@get external ok: response => bool = "ok"
@get external status: response => int = "status"
@send external text: response => promise<string> = "text"
@send external arrayBuffer: response => promise<ArrayBuffer.t> = "arrayBuffer"

type hash
@module("node:crypto") external createHash: string => hash = "createHash"
@send external update: (hash, Uint8Array.t) => hash = "update"
@send external digest: (hash, string) => string = "digest"

type spawned = {status: Nullable.t<int>, stdout: string, stderr: string}
type options = {encoding: string}
@module("node:child_process")
external spawnSync: (string, array<string>, options) => spawned = "spawnSync"
