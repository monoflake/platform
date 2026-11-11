/*** The footing's constants command takes its scaled facts from the contract, RFC w0w82. */
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

test("footing design facts retain their real units and lease range", () => {
  deepEqual(
    Footings.interface_.bounds->Option.map(bounds => [
      bounds->Dict.get("lease_seconds_default"),
      bounds->Dict.get("lease_seconds_most"),
      bounds->Dict.get("change_rows"),
    ]),
    Some([Some(30), Some(300), Some(100)]),
  )
})

test("the footing command scales the model facts to the existing TLC search", () => {
  let ran = spawn(
    executable,
    ["model/protocol/constants/footing_constants.res.mjs"],
    {cwd: root, encoding: "utf8"},
  )
  deepEqual(ran.status->Nullable.toOption, Some(0))
  deepEqual(
    JSON.parseOrThrow(ran.stdout),
    JSON.Object(
      dict{
        "Seconds": JSON.Number(2.),
        "Rows": JSON.Number(2.),
      },
    ),
  )
  let config = readText(`${root}model/protocol/footing.cfg`, "utf8")
  deepEqual(config->String.includes("\n\tSeconds = 2\n"), true)
  deepEqual(config->String.includes("\n\tRows = 2\n"), true)
})
