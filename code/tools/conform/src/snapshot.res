/***
 * What conform writes of a target once its run ends, RFC s42ex, in the shape of
 * `model/graph/snapshots.res`, one JSON file for each target under the snapshots directory.
 */

/** One contract's cases as the runner counted them, each case once in each form. */
type counted = {passed: int, failed: int, waiting: int, skipped: int}

/** The revision is what the live driver reports it was built from, absent where it reports none. */
type snapshot = {
  target: string,
  revision?: string,
  checkout: string,
  at: string,
  contracts: dict<counted>,
}

/** Where the files are written, `Snapshots.directory`. */
let directory = "~/.local/state/workspace/snapshots/"

/** A path with a leading `~` taken for the home directory. */
let expanded = (path, ~home) =>
  path->String.startsWith("~/") ? home ++ path->String.slice(~start=1) : path

/** The file of a target, named for it as conform was given it, or why it can be no file's name. */
let pathOf = (~home, target) =>
  target == "" || target->String.includes("/")
    ? Error(`${target == "" ? "no target" : target}: not a name for a file`)
    : {
        let base = expanded(directory, ~home)
        let base = base->String.endsWith("/") ? base : base ++ "/"
        Ok(`${base}${target}.json`)
      }

/** The commit id jj printed, or `unknown` where it did not run. */
let checkout = (printed: result<string, string>) =>
  switch printed {
  | Ok(text) if text->String.trim != "" => text->String.trim
  | Ok(_) | Error(_) => "unknown"
  }

let toJson = (snapshot: snapshot) => {
  let number = n => JSON.Number(Int.toFloat(n))
  JSON.Object(
    Dict.fromArray(
      [
        ("target", JSON.String(snapshot.target)),
        ...snapshot.revision->Option.mapOr([], r => [("revision", JSON.String(r))]),
        ("checkout", JSON.String(snapshot.checkout)),
        ("at", JSON.String(snapshot.at)),
        (
          "contracts",
          JSON.Object(
            snapshot.contracts->Dict.mapValues(c => JSON.Object(
              dict{
                "passed": number(c.passed),
                "failed": number(c.failed),
                "waiting": number(c.waiting),
                "skipped": number(c.skipped),
              },
            )),
          ),
        ),
      ],
    ),
  )
}

let whole = (o, key) =>
  o->Dict.get(key)->Option.flatMap(JSON.Decode.float)->Option.map(n => Float.toInt(n))

/** The counts the runner wrote, an object from each interface's name to its four numbers. */
let readCounts = text =>
  switch JSON.parseOrThrow(text)->JSON.Decode.object {
  | None => Error("no JSON object")
  | Some(contracts) =>
    let read = Dict.make()
    let bad = ref(None)
    contracts->Dict.forEachWithKey((json, name) =>
      switch json->JSON.Decode.object {
      | Some(o) =>
        switch (whole(o, "passed"), whole(o, "failed"), whole(o, "waiting"), whole(o, "skipped")) {
        | (Some(passed), Some(failed), Some(waiting), Some(skipped)) =>
          read->Dict.set(name, {passed, failed, waiting, skipped})
        | _ => bad := Some(name)
        }
      | None => bad := Some(name)
      }
    )
    switch bad.contents {
    | None => Ok(read)
    | Some(name) => Error(`${name}: not four numbers`)
    }
  | exception JsExn(_) => Error("no JSON")
  }

/** The snapshot written to its target's file, the directory made if missing, and the path. */
let write = (snapshot, ~home) =>
  pathOf(~home, snapshot.target)->Result.flatMap(path =>
    try {
      Host.mkdir(expanded(directory, ~home), {recursive: true})
      Host.writeText(path, JSON.stringify(toJson(snapshot), ~space=2) ++ "\n")
      Ok(path)
    } catch {
    | JsExn(e) => Error(`${path}: ${e->JsExn.message->Option.getOr("not written")}`)
    }
  )
