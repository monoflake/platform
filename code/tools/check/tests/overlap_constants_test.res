/*** The overlap's constants command prints the model's values, each one overlap.cfg declares. */
open Testing

type url
@new external url: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external pathOf: url => string = "fileURLToPath"
@module("node:process") external executable: string = "execPath"
@module("node:fs") external readText: (string, string) => string = "readFileSync"

type options = {cwd: string, encoding: string}
type spawned = {status: Nullable.t<int>, stdout: string}
@module("node:child_process")
external spawn: (string, array<string>, options) => spawned = "spawnSync"

let root = url("../../../../", importMetaUrl)->pathOf

test("the command prints Reach from the model, a constant overlap.cfg declares", () => {
  let ran = spawn(
    executable,
    ["model/protocol/constants/overlap_constants.res.mjs"],
    {cwd: root, encoding: "utf8"},
  )
  deepEqual(ran.status->Nullable.toOption, Some(0))
  let printed = JSON.parseOrThrow(ran.stdout)
  deepEqual(printed, JSON.Object(dict{"Reach": JSON.Number(Int.toFloat(Window.reach))}))
  let config = readText(`${root}model/protocol/overlap.cfg`, "utf8")
  deepEqual(config->String.includes("\n\tReach = "), true)
})
