/***
 * `Extension` held to `tests/extensions/`, a file for each computation, each read as it stands and
 * each record compared as its contract writes it.
 */
open Node
open Sample

let bound = "tests/extensions/bound.json"
let force = "tests/extensions/force.json"
let composed = "tests/extensions/composed.json"
let applied = "tests/extensions/applied.json"
let loans = "tests/extensions/loans.json"

/** What a case expects, the record as JSON or every failure. */
let expected = (case, record, failures, failure) =>
  switch (member(case, record), member(case, failures)) {
  | (Some(json), None) => Ok(json)
  | (None, Some(json)) => Error(json->items->Array.map(failure))
  | _ => fail(case, `no one of ${record} and ${failures}`)
  }

let cases = (path, name) => read(path)->at([name])->items

test("a binding made from its host as its sample says", () =>
  cases(bound, "cases")->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got =
      Extension.bind(case->at(["declared"])->declared, case->at(["binding"])->binding)->Result.map(
        Contracts.Extension.toJson,
      )
    deepEqual(got, expected(case, "bound", "unbound", unbound), ~message)
  })
)

test("the grace and quota in force as their sample says", () =>
  cases(force, "cases")->Array.forEach(case => {
    let message = case->at(["what"])->string
    let extension = case->at(["extension"])->decoded(Contracts.Extension.fromJson)
    let organization = case->at(["organization"])->decoded(Contracts.Organization.fromJson)
    deepEqual(
      Extension.grace(extension, ~organization),
      case->at(["grace"])->number,
      ~message=`${message}, its grace`,
    )
    deepEqual(
      Extension.quota(extension, ~organization),
      case->optional("quota", number),
      ~message=`${message}, its quota`,
    )
  })
)

test("a year and a week in seconds", () => {
  deepEqual(Extension.year, 31536000.)
  deepEqual(Extension.week, 604800.)
})

test("the levels a set composes to as their sample says", () =>
  cases(composed, "cases")->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got =
      Extension.compose(
        case->at(["set"])->set,
        case->at(["members"])->items->Array.map(member_),
      )->Option.map(Contracts.Placement.toJson)
    deepEqual(got, case->optional("composed", json => json), ~message)
  })
)

test("the list a driver is sent as its sample says", () =>
  cases(applied, "cases")->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got =
      Extension.apply(
        case->at(["listed"])->items->Array.map(listed),
        ~extension=case->at(["extension"])->number,
        ~generation=case->at(["generation"])->number,
        ~tokens=?case->optional("tokens", json => json->items->Array.map(hash)),
      )->Result.map(Contracts.ManagementApply.toJson)
    deepEqual(got, expected(case, "applied", "unlisted", unlisted), ~message)
  })
)

test("what crosses of a loan as its sample says", () =>
  cases(loans, "lent")->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got = Extension.lend(
      case->at(["extension"])->decoded(Contracts.Extension.fromJson),
      ~quota=case->at(["quota"])->number,
    )
    deepEqual(Contracts.AuthorityLoan.toJson(got), case->at(["loan"]), ~message)
  })
)

test("the borrower's binding of a loan as its sample says", () =>
  cases(loans, "borrowed")->Array.forEach(case => {
    let message = case->at(["what"])->string
    let got =
      Extension.borrow(
        case->at(["loan"])->decoded(Contracts.AuthorityLoan.fromJson),
        ~lender=case->at(["lender"])->decoded(Contracts.ExtensionLender.fromJson),
        ~token=case->at(["token"])->sealed,
        ~relays=case->at(["relays"])->relays,
      )->Result.map(Contracts.Extension.toJson)
    deepEqual(got, expected(case, "borrowed", "unbound", unbound), ~message)
  })
)
