open Node

test("kind takes one known directory and leaves the other arguments", () => {
  Selection.kinds->Array.forEach(kind =>
    deepEqual(
      Selection.flagged(["local", "--kind", kind, "--dry-run"]),
      Ok((Some(kind), ["local", "--dry-run"])),
    )
  )
  deepEqual(Selection.flagged(["local"]), Ok((None, ["local"])))
  ok(Selection.flagged(["local", "--kind", "unknown"])->Result.isError)
  ok(Selection.flagged(["local", "--kind"])->Result.isError)
  ok(Selection.flagged(["local", "--kind", "--dry-run"])->Result.isError)
})

test("an unknown kind is refused with usage before any target is accepted", () => {
  let done = Host.spawnSync(
    Host.execPath,
    [
      Host.fromRoot("code/tools/conform/src/main.res.mjs"),
      "--unused",
      "--app",
      "0123abcd",
      "--kind",
      "unknown",
    ],
    {stdio: ["pipe", "pipe", "pipe"], encoding: "utf8"},
  )
  deepEqual(done.status->Nullable.toOption, Some(2))
  let error = done.stderr->Nullable.toOption->Option.getOr("")
  ok(error->String.includes("--kind unknown is unknown"))
  ok(error->String.includes("conform <target> --app <id> [--kind <kind>]"))
})

test("each kind selects only its files and counts both forms of its cases", () => {
  let all = Selection.samples(None)
  Selection.kinds->Array.forEach(kind => {
    let files = Selection.samples(Some(kind))
    let expected = all->Array.filter(((path, _)) => path->String.startsWith(`tests/kinds/${kind}/`))
    ok(files->Array.length > 0)
    deepEqual(files, expected)
    deepEqual(Selection.count(files), expected->Array.reduce(0, (n, (_, cases)) => n + cases * 2))
    ok(Selection.count(files) < Selection.count(all))
  })
  deepEqual(
    Selection.samples(None),
    Selection.kinds->Array.flatMap(kind => Selection.samples(Some(kind))),
  )
})

test("partial runs skip snapshot writing and removal even without counts", () => {
  let home = mkdtemp(`${tmpdir()}/conform-selection-`)
  let snapshot: Snapshot.snapshot = {
    target: "local",
    checkout: "original",
    at: "2026-11-02T00:00:00.000Z",
    contracts: dict{},
  }
  let path = switch Snapshot.write(snapshot, ~home) {
  | Ok(path) => path
  | Error(why) => JsError.throwWithMessage(why)
  }
  let original = readText(path)
  ok(
    Selection.snapshotted(Some("objects"), () => {
      Snapshot.write({...snapshot, checkout: "changed"}, ~home)->ignore
      false
    }),
  )
  deepEqual(readText(path), original)
  ok(
    Selection.snapshotted(Some("objects"), () => {
      rm(path, {recursive: false, force: true})
      false
    }),
  )
  deepEqual(readText(path), original)
  let called = ref(false)
  ok(
    !Selection.snapshotted(None, () => {
      called := true
      false
    }),
  )
  ok(called.contents)
  rm(home, {recursive: true, force: true})
})

test("partial results name the kind without claiming the target's contracts", () => {
  deepEqual(
    Selection.finished(Some("objects"), ~target="local", ~met=true),
    "local partial run for objects, passed",
  )
  deepEqual(
    Selection.finished(Some("databases"), ~target="local", ~met=false),
    "local partial run for databases, failed",
  )
  deepEqual(
    Selection.finished(None, ~target="local", ~met=true),
    "local meets its contracts, but what waits",
  )
  deepEqual(
    Selection.finished(None, ~target="local", ~met=false),
    "local does not meet its contracts",
  )
})
