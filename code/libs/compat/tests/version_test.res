/***
 * `Version` held to `tests/compat/versions.json` and `written.json`, read as they stand.
 * `version.rs` beside it is the same in Rust.
 */
open Node
open Sample

let versions = "tests/compat/versions.json"
let written = "tests/compat/written.json"

/** A version that must be one. */
let made = json =>
  switch json->number->Version.make {
  | Some(version) => version
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no version`)
  }

/** A sample's `[lowest, highest]`, as a range or none. */
let range = json =>
  switch json->items {
  | [lowest, highest] => Version.range(made(lowest), made(highest))
  | _ => JsError.throwWithMessage(`${JSON.stringify(json)}: no pair`)
  }

let madeRange = json =>
  switch range(json) {
  | Some(range) => range
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: unmade`)
  }

test("every number is a version or not as its sample says", () => {
  let sample = read(versions)
  sample
  ->at(["made"])
  ->items
  ->Array.forEach(json =>
    deepEqual((made(json) :> float), number(json), ~message=JSON.stringify(json))
  )
  sample
  ->at(["unmade"])
  ->items
  ->Array.forEach(json =>
    deepEqual(json->number->Version.make, None, ~message=JSON.stringify(json))
  )
  deepEqual(Version.make(Version.max)->Option.map(v => (v :> float)), Some(Version.max))
  deepEqual(Version.make(Version.max +. 1.), None)
})

test("every range is made or not as its sample says", () => {
  let sample = read(versions)
  sample
  ->at(["ranges", "made"])
  ->items
  ->Array.forEach(json => {
    let message = JSON.stringify(json)
    let range = madeRange(json)
    deepEqual([range.lowest, range.highest], json->items->Array.map(made), ~message)
  })
  sample
  ->at(["ranges", "unmade"])
  ->items
  ->Array.forEach(json => deepEqual(range(json), None, ~message=JSON.stringify(json)))
})

test("every read is read or refused as its sample says", () =>
  read(versions)
  ->at(["reads"])
  ->items
  ->Array.forEach(case => {
    let range = case->at(["range"])->madeRange
    let version = case->at(["version"])->made
    let expected = switch case->member("refused")->Option.map(string) {
    | None => Ok()
    | Some("older") => Error(Version.Older({version, range}))
    | Some("newer") => Error(Version.Newer({version, range}))
    | Some(other) => JsError.throwWithMessage(`refused as ${other}`)
    }
    deepEqual(Version.reads(range, version), expected, ~message=JSON.stringify(case))
  })
)

test("every case writes its version or none as its sample says", () =>
  read(written)
  ->at(["cases"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let ranges = case->at(["ranges"])->items->Array.map(madeRange)
    let expected = switch (case->member("written"), case->member("unchosen")) {
    | (Some(written), None) => Ok(made(written))
    | (None, Some(unchosen)) =>
      switch unchosen->JSON.Decode.string {
      | Some("empty") => Error(Version.Empty)
      | Some(other) => JsError.throwWithMessage(`${message}: unchosen as ${other}`)
      | None =>
        Error(
          Version.Apart({
            highest: unchosen->at(["highest"])->made,
            above: unchosen->at(["above"])->items->Array.map(at => at->number->Float.toInt),
          }),
        )
      }
    | (Some(_), Some(_)) | (None, None) =>
      JsError.throwWithMessage(`${message}: neither written nor unchosen`)
    }
    deepEqual(Version.written(ranges), expected, ~message)
  })
)
