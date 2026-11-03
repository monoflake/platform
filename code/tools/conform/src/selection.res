let kinds = ["management", "deployments", "objects", "databases"]

let flagged = args =>
  switch args->Array.indexOf("--kind") {
  | -1 => Ok((None, args))
  | at =>
    switch args->Array.get(at + 1) {
    | Some(kind) if kinds->Array.includes(kind) =>
      Ok((Some(kind), args->Array.filterWithIndex((_, i) => i != at && i != at + 1)))
    | Some(kind) => Error(`--kind ${kind} is unknown, choose ${kinds->Array.join(", ")}`)
    | None => Error("--kind names no kind")
    }
  }

/** Every selected behavior file and how many cases it holds. */
let samples = kind =>
  kind
  ->Option.mapOr(kinds, kind => [kind])
  ->Array.flatMap(kind => {
    let directory = `tests/kinds/${kind}`
    Host.list(Host.fromRoot(directory))
    ->Array.filter(name => name->String.endsWith(".json"))
    ->Array.toSorted(String.compare)
    ->Array.map(name => {
      let path = `${directory}/${name}`
      let cases =
        JSON.parseOrThrow(Host.readText(Host.fromRoot(path)))
        ->JSON.Decode.object
        ->Option.flatMap(o => o->Dict.get("cases"))
        ->Option.flatMap(JSON.Decode.array)
        ->Option.mapOr(0, Array.length)
      (path, cases)
    })
  })

let count = files => files->Array.reduce(0, (n, (_, cases)) => n + cases * 2)

/** A partial run neither writes nor removes a target's snapshot. */
let snapshotted = (kind, whole) =>
  switch kind {
  | Some(_) => true
  | None => whole()
  }

let finished = (kind, ~target, ~met) =>
  switch kind {
  | Some(kind) => `${target} partial run for ${kind}, ${met ? "passed" : "failed"}`
  | None =>
    `${target} ${met ? "meets its contracts, but what waits" : "does not meet its contracts"}`
  }
