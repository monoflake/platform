/***
 * Builds every fixture of `tests/fixtures/` into a directory, its manifest beside them, RFC p8e8k,
 * as `usage` says, and prints what it built and what it did not.
 */
let usage = "node src/build.res.mjs --into <directory> [--bounds <json file>] [--architecture <arm64 or amd64>]"

let refuse = why => {
  Console.error(`build: ${why}`)
  System.setExitCode(System.process, 2)
}

let rec parse = (args, flags) =>
  switch args {
  | list{flag, value, ...rest} if flag->String.startsWith("--") =>
    flags->Dict.set(flag->String.slice(~start=2), value)
    parse(rest, flags)
  | list{} => Ok(flags)
  | list{other, ..._} => Error(`${other} is no flag with its value`)
  }

let bounds = path =>
  switch JSON.parseOrThrow(System.readFileSync(path))->JSON.Decode.object {
  | Some(o) =>
    Ok(
      o
      ->Dict.toArray
      ->Array.filterMap(((name, n)) => n->JSON.Decode.float->Option.map(n => (name, n)))
      ->Dict.fromArray,
    )
  | None => Error(`${path}: no JSON object`)
  | exception JsExn(e) => Error(`${path}: ${e->JsExn.message->Option.getOr("not read")}`)
  }

switch parse(List.fromArray(System.argv->Array.slice(~start=2)), Dict.make()) {
| Error(why) => refuse(`${why}; ${usage}`)
| Ok(flags) =>
  switch (flags->Dict.get("into"), flags->Dict.get("bounds")->Option.mapOr(Ok(dict{}), bounds)) {
  | (None, _) => refuse(usage)
  | (_, Error(why)) => refuse(why)
  | (Some(into), Ok(bounds)) =>
    let manifest = Fixtures.build(~into, ~bounds, ~architecture=flags->Dict.get("architecture"))
    manifest.built->Dict.forEachWithKey((b, name) =>
      Console.log(`built ${name}, ${b.form}, ${b.hash}`)
    )
    manifest.unbuilt->Dict.forEachWithKey((why, name) => Console.log(`not built ${name}, ${why}`))
  }
}
