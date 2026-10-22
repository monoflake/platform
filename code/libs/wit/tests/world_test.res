/***
 * `World` held to `tests/wit/accepted.json`, `tests/wit/refused.json` and `tests/wit/matched.json`,
 * each with the WIT files it names, read as they stand.
 */
open Node
open Sample

let accepted = "tests/wit/accepted.json"
let refused = "tests/wit/refused.json"
let matched = "tests/wit/matched.json"

/** The world a file reads to, which a sample says it must. */
let world = path =>
  switch World.read(text(path)) {
  | Ok(world) => world
  | Error(refusals) =>
    JsError.throwWithMessage(`${path}: refused, ${refusals->Array.length->Int.toString} refusals`)
  }

test("each accepted file reads to the world its sample writes", () =>
  read(accepted)
  ->at(["accepted"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let read = world(case->at(["file"])->string)
    deepEqual(World.package(read), package(case), ~message)
    deepEqual(World.name(read), case->at(["name"])->string, ~message)
    deepEqual(World.imports(read), case->at(["imports"])->items->Array.map(function), ~message)
    deepEqual(World.exports(read), case->at(["exports"])->items->Array.map(function), ~message)
  })
)

test("each refused file is refused as its sample says, every refusal where it is", () =>
  read(refused)
  ->at(["refused"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got = World.read(lines(case))->Result.map(_ => ())
    deepEqual(got, Error(case->at(["refusals"])->items->Array.map(refusal)), ~message)
  })
)

test("each case's calls match the provider's exports as its sample says", () => {
  let sample = read(matched)
  let caller = world(sample->at(["caller"])->string)
  let exports = world(sample->at(["provider"])->string)->World.exports
  sample
  ->at(["cases"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let calls = case->at(["calls"])->items->Array.map(string)
    let expected = switch case->at(["mismatches"])->items->Array.map(mismatch) {
    | [] => Ok()
    | mismatches => Error(mismatches)
    }
    deepEqual(World.matches(caller, ~calls, ~exports), expected, ~message)
  })
})
