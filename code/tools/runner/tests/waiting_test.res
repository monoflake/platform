/***
 * `Waiting` held to reporting a case waiting where a rule says what its implementation does not do
 * yet, and as it ran everywhere else.
 */
open Node

let rules = switch Waiting.read(`[
  {"interface": "management", "operation": "apply", "naming": "4elqc", "on": "RFC 4elqc"},
  {"interface": "database", "naming": "no interface database", "on": "no database"}
]`) {
| Ok(rules) => rules
| Error(why) => JsError.throwWithMessage(why)
}

let case = switch Sample.read(`{
  "interface": "management",
  "cases": [{
    "description": "a list applied is held",
    "steps": [
      {"call": "set_policy", "input": {"policy": 1, "grace": 0}, "expect": {"output": {"$any": null}}},
      {"call": "apply", "input": {"generation": 1, "items": []}, "expect": {"output": {"$any": null}}}
    ]
  }]
}`) {
| Ok({cases: [case]}) => case
| Ok(_) | Error(_) => JsError.throwWithMessage("no case")
}

let fault = "expected an answer, answered unknown fault (not yet implemented: 4elqc)"

test("rules are read with what each names, and a file that writes none is refused", () => {
  deepEqual(
    rules,
    [
      {
        interface: Some("management"),
        operation: Some("apply"),
        naming: "4elqc",
        on: "RFC 4elqc",
      },
      {
        interface: Some("database"),
        operation: None,
        naming: "no interface database",
        on: "no database",
      },
    ],
  )
  ok(Waiting.read(`{}`)->Result.isError)
  ok(Waiting.read(`[{"naming": "x"}]`)->Result.isError)
  ok(Waiting.read(`not JSON`)->Result.isError)
})

test("a step a rule names, answered naming its text, waits on what the rule says", () =>
  deepEqual(
    Waiting.reported(rules, ~interface="management", ~case, Failed({step: 1, why: fault})),
    Waiting("RFC 4elqc"),
  )
)

test("a failure of another step, another interface or another answer is a failure still", () => {
  let failed: Run.outcome = Failed({step: 0, why: fault})
  deepEqual(Waiting.reported(rules, ~interface="management", ~case, failed), Ran(failed))
  let other: Run.outcome = Failed({step: 1, why: fault})
  deepEqual(Waiting.reported(rules, ~interface="object", ~case, other), Ran(other))
  let answered: Run.outcome = Failed({step: 1, why: "expected an answer, answered rejected stale"})
  deepEqual(Waiting.reported(rules, ~interface="management", ~case, answered), Ran(answered))
})

test("a rule naming no operation holds for every step of its interface", () => {
  let why = "expected an answer, answered rejected malformed (no interface database, one of x)"
  deepEqual(
    Waiting.reported(rules, ~interface="database", ~case, Failed({step: 0, why})),
    Waiting("no database"),
  )
})

test("a case passed or skipped is reported as it ran", () => {
  deepEqual(Waiting.reported(rules, ~interface="management", ~case, Passed), Ran(Passed))
  deepEqual(
    Waiting.reported(rules, ~interface="management", ~case, Skipped("a fixture")),
    Ran(Skipped("a fixture")),
  )
})
