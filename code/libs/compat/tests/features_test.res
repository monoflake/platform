/***
 * `Features` held to `tests/compat/features.json`, read as it stands. `features.rs` beside it is
 * the same in Rust.
 */
open Node
open Sample

let features = "tests/compat/features.json"

/** A sample's `{has, needs}`, as features or why not. */
let side = json => Features.make(~has=json->at(["has"])->names, ~needs=json->at(["needs"])->names)

let madeSide = json =>
  switch side(json) {
  | Ok(made) => made
  | Error(Name(name) | Unheld(name)) =>
    JsError.throwWithMessage(`${JSON.stringify(json)}: refused by ${name}`)
  }

test("every side is made sorted once as its sample says", () =>
  read(features)
  ->at(["made"])
  ->items
  ->Array.forEach(case => {
    let message = JSON.stringify(case)
    let made = madeSide(case)
    deepEqual(made.has, case->at(["made", "has"])->names, ~message)
    deepEqual(made.needs, case->at(["made", "needs"])->names, ~message)
  })
)

test("every side is refused by its first name as its sample says", () =>
  read(features)
  ->at(["unmade"])
  ->items
  ->Array.forEach(case => {
    let message = JSON.stringify(case)
    let malformed = case->at(["malformed"])
    let expected = switch (malformed->member("name"), malformed->member("unheld")) {
    | (Some(name), None) => Features.Name(string(name))
    | (None, Some(name)) => Features.Unheld(string(name))
    | (Some(_), Some(_)) | (None, None) =>
      JsError.throwWithMessage(`${message}: neither name nor unheld`)
    }
    deepEqual(side(case), Error(expected), ~message)
  })
)

test("every two sides agree or miss as their sample says", () =>
  read(features)
  ->at(["agreed"])
  ->items
  ->Array.forEach(case => {
    let message = JSON.stringify(case)
    let first = case->at(["first"])->madeSide
    let second = case->at(["second"])->madeSide
    let expected = switch (case->member("agreed"), case->member("missing")) {
    | (Some(agreed), None) => Ok(names(agreed))
    | (None, Some(missing)) =>
      Error({
        Features.first: missing->at(["first"])->names,
        second: missing->at(["second"])->names,
      })
    | (Some(_), Some(_)) | (None, None) =>
      JsError.throwWithMessage(`${message}: neither agreed nor missing`)
    }
    deepEqual(Features.agreed(first, second), expected, ~message)
  })
)
