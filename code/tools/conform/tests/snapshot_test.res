/***
 * `Snapshot` held to RFC s42ex, the file of a target, the shape written to it and the counts the
 * runner wrote read back.
 */
open Node

let counts = switch Snapshot.readCounts(`{
  "objects.write": {"passed": 4, "failed": 1, "waiting": 2, "skipped": 0},
  "management": {"passed": 6, "failed": 0, "waiting": 0, "skipped": 2}
}`) {
| Ok(counts) => counts
| Error(why) => JsError.throwWithMessage(why)
}

let snapshot: Snapshot.snapshot = {
  target: "root@machine.example",
  checkout: "0123abcd",
  at: "2026-10-24T12:00:00.000Z",
  contracts: counts,
}

test("a target's file is named for it under the directory, ~ the home directory", () => {
  deepEqual(
    Snapshot.pathOf(~home="/home/me", "root@machine.example"),
    Ok("/home/me/.local/state/workspace/snapshots/root@machine.example.json"),
  )
  ok(Snapshot.pathOf(~home="/home/me", "")->Result.isError)
  ok(Snapshot.pathOf(~home="/home/me", "../root")->Result.isError)
})

test("a snapshot is the target, checkout, time and each contract's four numbers", () => {
  deepEqual(
    JSON.stringify(Snapshot.toJson(snapshot)),
    `{"target":"root@machine.example","checkout":"0123abcd","at":"2026-10-24T12:00:00.000Z","contracts":{"objects.write":{"passed":4,"failed":1,"waiting":2,"skipped":0},"management":{"passed":6,"failed":0,"waiting":0,"skipped":2}}}`,
  )
})

test("the commit id jj printed is the checkout, unknown where jj did not run", () => {
  deepEqual(Snapshot.checkout(Ok("9f8e7d\n")), "9f8e7d")
  deepEqual(Snapshot.checkout(Ok("")), "unknown")
  deepEqual(Snapshot.checkout(Error("jj failed, not a repository")), "unknown")
})

test("counts that are no four numbers for an interface are refused", () => {
  ok(Snapshot.readCounts(`{"management": {"passed": 1}}`)->Result.isError)
  ok(Snapshot.readCounts(`[]`)->Result.isError)
  ok(Snapshot.readCounts(`not json`)->Result.isError)
  deepEqual(Snapshot.readCounts(`{}`)->Result.map(Dict.keysToArray), Ok([]))
})

test("a snapshot is written to its file, the directory made, and reads back as written", () => {
  let home = mkdtemp(`${tmpdir()}/snapshot-`)
  switch Snapshot.write(snapshot, ~home) {
  | Ok(path) =>
    deepEqual(path, `${home}/.local/state/workspace/snapshots/root@machine.example.json`)
    deepEqual(
      JSON.parseOrThrow(readText(path)),
      JSON.parseOrThrow(JSON.stringify(Snapshot.toJson(snapshot))),
    )
  | Error(why) => JsError.throwWithMessage(why)
  }
  rm(home, {recursive: true, force: true})
})
