/**
 * Every written block built, formatted, linted and tested alone, `mise run blocks`. One in work
 * that fails is listed in red and fails nothing, `model/plan/work.res`.
 */
open Base
open Blocks

type spawned = {status: Nullable.t<int>}
type options = {cwd: string, stdio: string}
@module("node:child_process")
external spawnSync: (string, array<string>, options) => spawned = "spawnSync"
@get external pathname: url => string = "pathname"

let (blocks, _, _) = expected()
let found = []
blocks->Map.forEachWithKey((h, path) =>
  if Code.held(path, h) != None {
    Console.log(`\n# Built ${h.package}`)
    let run = spawnSync(
      "mise",
      ["run", "built", h.package],
      {cwd: root->pathname, stdio: "inherit"},
    )
    if run.status->Nullable.toOption != Some(0) {
      let failing = `${h.package}: mise run built ${h.package} fails`
      Work.blocks->Dict.get(h.package) == Some(InWork)
        ? inWork->Array.push(failing)
        : found->Array.push(failing)
    }
  }
)
dimension(
  "Blocks",
  "Does every written block build, format, lint and pass its tests alone?",
  found,
  (),
)
shownInWork()
process->setExitCode(failed.contents ? 1 : 0)
