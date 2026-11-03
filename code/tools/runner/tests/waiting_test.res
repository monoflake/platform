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

let waiting = switch Waiting.read(readFileSync(fromRoot("code/tools/conform/waiting.json"))) {
| Ok(rules) => rules
| Error(why) => JsError.throwWithMessage(why)
}

let rewinds = switch Sample.read(readFileSync(fromRoot("tests/kinds/databases/rewinds.json"))) {
| Ok(file) => file
| Error(why) => JsError.throwWithMessage(why)
}

let hasWait = (case: Sample.case) =>
  case.steps->Array.some(step =>
    switch step {
    | Wait(_) => true
    | Call(_) | Send(_) | Lose(_) => false
    }
  )

test("conform's waiting rules drop rewinds.json waits and preserve every other step", () => {
  ok(rewinds.cases->Array.some(hasWait))
  let prepared = Waiting.file(waiting, rewinds)
  ok(!(prepared.cases->Array.some(hasWait)))
  deepEqual(
    prepared.cases->Array.flatMap(c => c.steps),
    rewinds.cases
    ->Array.flatMap(c => c.steps)
    ->Array.filter(step =>
      switch step {
      | Wait(_) => false
      | Call(_) | Send(_) | Lose(_) => true
      }
    ),
  )
})

test("a case calling no named operation and another interface keep their waits", () => {
  let unnamed: Sample.file = {
    ...rewinds,
    cases: [
      {...case, steps: [Sample.Wait(10)]->Array.concat(case.steps)->Array.concat([Wait(20)])},
    ],
  }
  deepEqual(Waiting.file(waiting, unnamed), unnamed)
  let other = {...rewinds, interface: "other"}
  deepEqual(Waiting.file(waiting, other), other)
})

test("a rule naming no operation drops nothing, and an unnamed interface matches", () => {
  let rule: Waiting.rule = {
    interface: None,
    operation: None,
    naming: "anything",
    on: "later",
  }
  deepEqual(Waiting.file([rule], rewinds), rewinds)
  deepEqual(Waiting.file([], rewinds), rewinds)
  ok(!(Waiting.file([{...rule, operation: Some("rewind")}], rewinds).cases->Array.some(hasWait)))
})

testAsync(
  "a dropped wait keeps the executed failure's operation and words for reporting",
  async () => {
    let file = Waiting.file(waiting, rewinds)
    let case = file.cases->Array.getUnsafe(0)
    let calls = []
    let waits = []
    let position = ref(0)
    let failure = ref("machine-rewind-by-wal")
    let target: Run.target = {
      call: async (
        ~interface as _,
        ~operation,
        ~input as _,
        ~form as _,
        ~as_ as _,
        ~bearer as _,
      ) => {
        calls->Array.push(operation)
        let step = case.steps->Array.get(position.contents)
        position := position.contents + 1
        switch step {
        | Some(Call({expect: Output(output)})) =>
          operation == "rewind" ? Error(failure.contents) : Ok(Run.Answered(output))
        | Some(Call({expect: Answer(_) | Failure(_)}))
        | Some(Send(_) | Lose(_) | Wait(_))
        | None =>
          Error(failure.contents)
        }
      },
      send: async (~to as _, ~export as _, ~key as _, ~body as _, ~form as _) => Error("no send"),
      given: async (~interface as _, ~form as _, _) => {
        position := 0
        Ok()
      },
      lose: async _ => Ok(),
      bound: _ => None,
      fixture: _ => Error("no fixture"),
      signed: (_, _) => Error("no signature"),
      now: () => 0.,
      wait: async ms => waits->Array.push(ms),
      network: false,
      tunnel: false,
      captured: dict{},
    }
    let file = {...file, cases: [case]}
    let results = await Run.file(file, target)
    let why = "expected an answer, answered nothing: machine-rewind-by-wal"
    let outcome: Run.outcome = Failed({step: 2, why})
    deepEqual(
      results,
      [{description: case.description, outcomes: [(Cbor, outcome), (Json, outcome)]}],
    )
    deepEqual(calls, ["execute", "execute", "rewind", "execute", "execute", "rewind"])
    deepEqual(waits, [])
    ok(Waiting.reported(waiting, ~interface=file.interface, ~case, outcome) != Ran(outcome))
    failure := "rewind now serves but fails otherwise"
    let results = await Run.file(file, target)
    results->Array.forEach(result =>
      result.outcomes->Array.forEach(
        ((_, outcome)) => {
          ok(outcome != Passed)
          deepEqual(
            Waiting.reported(waiting, ~interface=file.interface, ~case, outcome),
            Ran(outcome),
          )
        },
      )
    )
  },
)
