/***
 * What the generator takes of node, since it runs while the platform is built and never in it: its
 * arguments and exit, its files, and ReScript's formatter run as a child.
 */
@module("node:process") external argv: array<string> = "argv"
@module("node:process") external exit: int => unit = "exit"

@module("node:fs") external readFileSync: (string, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external writeFileSync: (string, string) => unit = "writeFileSync"
type made = {recursive: bool}
@module("node:fs") external mkdirSync: (string, made) => unit = "mkdirSync"

type spawned = {status: Nullable.t<int>}
type options = {stdio: string}
@module("node:child_process")
external spawnSync: (string, array<string>, options) => spawned = "spawnSync"
