/*** `Held` held to `tests/scope/held.json`, read as it stands, over the model's vocabulary. */
open Node
open Sample

let held = "tests/scope/held.json"

/** The scope a case's bundle holds, which a case of `held` must have. */
let scope = case =>
  switch Held.read(case->at(["bundle"])->bundle, ~scope=case->at(["scope"])->number) {
  | Ok(scope) => scope
  | Error(_) => JsError.throwWithMessage(`${case->at(["what"])->string}: no scope read`)
  }

test("a scope's status read from its bundle as its sample says", () =>
  read(held)
  ->at(["held"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    deepEqual(Held.status(scope(case)), case->at(["status"])->status, ~message)
  })
)

test("a scope's allowance read with its defaults filled as its sample says", () =>
  read(held)
  ->at(["held"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    deepEqual(Held.allowance(scope(case)), case->at(["allowance"])->values, ~message)
  })
)

test("a need fits a scope, or is refused, as its sample says", () =>
  read(held)
  ->at(["held"])
  ->items
  ->Array.forEach(case => {
    let scope = scope(case)
    case
    ->at(["fits"])
    ->items
    ->Array.forEach(
      fit => {
        let message = `${case->at(["what"])->string}, ${fit->at(["what"])->string}`
        let got = Held.fits(scope, ~need=fit->at(["need"])->needs)
        deepEqual(got, fit->at(["refused"])->refused, ~message)
      },
    )
  })
)

test("a bundle holding no scope by the id asked refused as its sample says", () =>
  read(held)
  ->at(["unheld"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got =
      Held.read(case->at(["bundle"])->bundle, ~scope=case->at(["scope"])->number)->Result.map(
        _ => (),
      )
    deepEqual(got, Error(case->at(["unheld"])->unheld), ~message)
  })
)
