/**
 * Every library a tool writes has its ReScript written again, `mise run generate [<package>]`,
 * `model/graph/tools.res`. Its Rust is cargo's to run by `build.rs`.
 */
open Base
open Blocks

type spawned = {status: Nullable.t<int>}
type options = {cwd: string, stdio: string}
@module("node:child_process")
external spawnSync: (string, array<string>, options) => spawned = "spawnSync"
@get external pathname: url => string = "pathname"

let run = (command, arguments) =>
  spawnSync(
    command,
    arguments,
    {cwd: root->pathname, stdio: "inherit"},
  ).status->Nullable.toOption == Some(0)

let named = args->Array.slice(~start=2)->Array.get(0)
let (blocks, _, _) = expected()
blocks->Map.forEachWithKey((h, path) =>
  switch h.writtenBy {
  | Some(tool)
    if h.languages->Array.includes(#rescript) && named->Option.mapOr(true, n => n == h.package) =>
    let at = `code/tools/${tool}`
    let written =
      run("rescript", ["build", at]) &&
      run("node", [`${at}/src/main.res.mjs`, "model/contracts.json", `${path}/generated`])
    if !written {
      Console.error(`${h.package}: ${tool} wrote nothing`)
      process->setExitCode(1)
    }
  | Some(_) | None => ()
  }
)
