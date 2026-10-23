/***
 * What an implementation knowingly does not do yet, a rule each from a file a run is given, so a
 * case it stops is reported waiting rather than failed, as a driver's own tests tell them apart.
 */

/**
 * A step answered naming a text, of any interface and operation unless the rule names one, and
 * what the step waits on.
 */
type rule = {interface: option<string>, operation: option<string>, naming: string, on: string}

let field = (o, name) => o->Dict.get(name)->Option.flatMap(JSON.Decode.string)

/** The rules a file's JSON writes, an array of them, or why it is none. */
let read = text =>
  switch JSON.parseOrThrow(text)->JSON.Decode.array {
  | None => Error("no array of rules")
  | Some(rules) =>
    rules->Array.reduce(Ok([]), (read, json) =>
      read->Result.flatMap(rules =>
        switch json->JSON.Decode.object {
        | Some(o) =>
          switch (field(o, "naming"), field(o, "on")) {
          | (Some(naming), Some(on)) =>
            Ok(
              rules->Array.concat([
                {interface: field(o, "interface"), operation: field(o, "operation"), naming, on},
              ]),
            )
          | _ => Error("a rule names no naming or no on")
          }
        | None => Error("a rule that is no object")
        }
      )
    )
  | exception JsExn(_) => Error("no JSON")
  }

/** What a case's outcome in a form is reported as, waiting on what a rule says or as it ran. */
type reported = Ran(Run.outcome) | Waiting(string)

let reported = (rules, ~interface, ~case: Sample.case, outcome: Run.outcome) =>
  switch outcome {
  | Passed | Skipped(_) => Ran(outcome)
  | Failed({step, why}) =>
    let operation = switch case.steps->Array.get(step) {
    | Some(Call({operation})) => Some(operation)
    | Some(Send(_) | Lose(_) | Wait(_)) | None => None
    }
    let holds = (rule: rule) =>
      rule.interface->Option.mapOr(true, i => i == interface) &&
      rule.operation->Option.mapOr(true, o => Some(o) == operation) &&
      why->String.includes(rule.naming)
    switch rules->Array.find(holds) {
    | Some(rule) => Waiting(rule.on)
    | None => Ran(outcome)
    }
  }
