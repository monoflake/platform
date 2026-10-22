/***
 * `Needs` held to `tests/vocabulary/compared.json`, a vocabulary of its own with an entry of every
 * type, and to `tests/vocabulary/model.json`, the model's, each read as it stands.
 */
open Node
open Sample

let compared = "tests/vocabulary/compared.json"
let model = "tests/vocabulary/model.json"

/** The vocabulary a sample's entries make. */
let made = sample =>
  switch sample->at(["entries"])->items->Array.map(entry)->Needs.make {
  | Ok(vocabulary) => vocabulary
  | Error(_) => JsError.throwWithMessage(`${JSON.stringify(sample)}: its entries refused`)
  }

let malformed = (json): Needs.malformed =>
  switch (member(json, "name"), member(json, "repeated"), member(json, "default")) {
  | (Some(name), None, None) => Name(string(name))
  | (None, Some(name), None) => Repeated(string(name))
  | (None, None, Some(name)) => Default(string(name))
  | _ => JsError.throwWithMessage(`${JSON.stringify(json)}: no one malformed`)
  }

/** Every case of `filled`, `fits` and `meets` a sample holds, against its vocabulary. */
let holds = (sample, vocabulary) => {
  sample
  ->at(["filled"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got = Needs.filled(vocabulary, case->at(["side"])->side, case->at(["values"])->values)
    deepEqual(got, case->at(["filled"])->values, ~message)
  })
  sample
  ->at(["fits"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let need = case->at(["need"])->values
    let allowance = case->at(["allowance"])->values
    deepEqual(Needs.fits(vocabulary, ~need, ~allowance), expected(case), ~message)
  })
  sample
  ->at(["meets"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let need = case->at(["need"])->values
    let offer = case->at(["offer"])->values
    deepEqual(Needs.meets(vocabulary, ~need, ~offer), expected(case), ~message)
  })
}

test("the model's vocabulary is the one its sample writes", () =>
  deepEqual(Needs.entries(Needs.model), read(model)->at(["entries"])->items->Array.map(entry))
)

test("entries make a vocabulary, kept in their order", () => {
  let sample = read(compared)
  let entries = sample->at(["entries"])->items->Array.map(entry)
  deepEqual(Needs.entries(made(sample)), entries)
})

test("entries are refused by the first malformed as their sample says", () =>
  read(compared)
  ->at(["unmade"])
  ->items
  ->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got = case->at(["entries"])->items->Array.map(entry)->Needs.make->Result.map(_ => ())
    deepEqual(got, Error(malformed(case->at(["malformed"]))), ~message)
  })
)

test("every type filled and compared as its sample says", () => {
  let sample = read(compared)
  holds(sample, made(sample))
})

test("the model's vocabulary filled and compared as its sample says", () =>
  holds(read(model), Needs.model)
)
