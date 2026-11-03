/***
 * `Counts` held to summing every file of one interface into one entry, and writing each
 * interface's four numbers by its name.
 */
open Node

test("the files of one interface are summed and another's kept apart", () => {
  let counts = Dict.make()
  counts->Counts.add(~interface="objects.write", {passed: 4, failed: 1, waiting: 2, skipped: 0})
  counts->Counts.add(~interface="management", {passed: 6, failed: 0, waiting: 0, skipped: 2})
  counts->Counts.add(~interface="objects.write", {passed: 2, failed: 0, waiting: 1, skipped: 3})
  deepEqual(
    counts->Dict.keysToArray->Array.toSorted(String.compare),
    ["management", "objects.write"],
  )
  deepEqual(
    counts->Dict.get("objects.write"),
    Some({Counts.passed: 6, failed: 1, waiting: 3, skipped: 3}),
  )
  deepEqual(
    counts->Dict.get("management"),
    Some({Counts.passed: 6, failed: 0, waiting: 0, skipped: 2}),
  )
})

test("the counts are written as an object from each interface to its four numbers", () => {
  let counts = Dict.make()
  counts->Counts.add(~interface="objects.write", {passed: 4, failed: 1, waiting: 2, skipped: 0})
  deepEqual(
    JSON.stringify(Counts.toJson(counts)),
    `{"objects.write":{"passed":4,"failed":1,"waiting":2,"skipped":0}}`,
  )
  deepEqual(JSON.stringify(Counts.toJson(Dict.make())), "{}")
})

test("each file's count line adds seconds while the total stays unchanged", () => {
  let directory = System.mkdtemp(`${System.tmpdir()}/runner-counts-`)
  let paths = ["first", "second"]->Array.map(name => `${directory}/${name}.json`)
  try {
    paths->Array.forEach(path => System.writeText(path, `{"interface":"objects.write","cases":[]}`))
    let done = System.spawnSync(
      "node",
      [
        System.rootPath("code/tools/runner/src/main.res.mjs"),
        "--base",
        "http://localhost:1",
        ...paths,
      ],
      {stdio: ["ignore", "pipe", "pipe"], encoding: "utf8"},
    )
    deepEqual(done.status->Nullable.toOption, Some(0))
    let lines = done.stdout->Nullable.getOr("")->String.trim->String.split("\n")
    let counts = lines->Array.filter(line => line->String.startsWith("  0 passed"))
    deepEqual(counts->Array.length, 2)
    counts->Array.forEach(line => {
      let prefix = "  0 passed, 0 failed, 0 waiting, 0 skipped, "
      ok(line->String.startsWith(prefix))
      ok(line->String.endsWith("s"))
      let seconds = line->String.slice(~start=prefix->String.length, ~end=-1)
      let parsed = seconds->Float.fromString->Option.getOr(-1.)
      ok(parsed >= 0.)
      deepEqual(seconds, parsed->Float.toFixed(~digits=1))
    })
    deepEqual(
      lines->Array.get(lines->Array.length - 1),
      Some(
        "0 passed, 0 failed, 0 waiting, 0 skipped, each case once in each form, of 2 behavior files",
      ),
    )
    System.rm(directory, {recursive: true, force: true})
  } catch {
  | error =>
    System.rm(directory, {recursive: true, force: true})
    throw(error)
  }
})
