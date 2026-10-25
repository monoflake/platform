/***
 * A target's calls made as the operator by the credential the run holds, on an operation the model
 * declares the operator's alone, and the organization the run is told, RFC 8j7b0.
 */

/** The name a step is called `as` to carry the operator's credential. */
let operator = "operator"

/** Where the operator's credential is read from, as the deploy tool reads it. */
let variable = "CONTROL_OPERATOR"

/** The name every case begins with the run's organization captured by. */
let organization = "organization"

/** The operations whose callers in contracts.json include the operator, `interface/operation`. */
let operated = (contracts: JSON.t) => {
  let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
  contracts
  ->field("interfaces")
  ->Option.flatMap(JSON.Decode.object)
  ->Option.mapOr([], interfaces =>
    interfaces
    ->Dict.toArray
    ->Array.flatMap(((interface, i)) =>
      i
      ->field("operations")
      ->Option.flatMap(JSON.Decode.array)
      ->Option.getOr([])
      ->Array.filterMap(
        o =>
          switch (
            o->field("name")->Option.flatMap(JSON.Decode.string),
            o->field("callers")->Option.flatMap(JSON.Decode.array)->Option.getOr([]),
          ) {
          | (Some(name), callers) if callers->Array.includes(JSON.String(operator)) =>
            Some(`${interface}/${name}`)
          | (Some(_) | None, _) => None
          },
      )
    )
  )
}

/**
 * The target, a call `as` the operator carrying its credential as the bearer, on an operation
 * `operated` names alone.
 */
let target = (
  target: Run.target,
  ~credential: option<string>,
  ~operated: array<string>,
): Run.target => {
  ...target,
  call: (~interface, ~operation, ~input, ~form, ~as_, ~bearer) =>
    switch (as_, credential) {
    | (Some(name), _)
      if name == operator && !(operated->Array.includes(`${interface}/${operation}`)) =>
      Promise.resolve(
        Error(
          `${interface} ${operation} is no operation of the operator's, by the model's callers`,
        ),
      )
    | (Some(name), Some(credential)) if name == operator =>
      target.call(~interface, ~operation, ~input, ~form, ~as_=None, ~bearer=Some(credential))
    | (Some(name), None) if name == operator =>
      Promise.resolve(Error(`a call as the operator, yet no ${variable} is given`))
    | (Some(_) | None, _) => target.call(~interface, ~operation, ~input, ~form, ~as_, ~bearer)
    },
}

/** Whether a value holds `{"$use": "organization"}` anywhere within it. */
let rec uses = (json: JSON.t) =>
  switch (json->JSON.Decode.object, json->JSON.Decode.array) {
  | (Some(o), _) =>
    o->Dict.toArray == [("$use", JSON.String(organization))] ||
      o->Dict.valuesToArray->Array.some(uses)
  | (None, Some(items)) => items->Array.some(uses)
  | (None, None) => false
  }

/** Whether a case uses the run's organization, in an input, a send or what a step expects. */
let usedBy = (case: Sample.case) => {
  let expected = (expect: Sample.expect) =>
    switch expect {
    | Output(json) | Answer(json) => uses(json)
    | Failure(_) => false
    }
  case.steps->Array.some(step =>
    switch step {
    | Call({input, expect}) => uses(input) || expected(expect)
    | Send({send, expect}) =>
      uses(send.to) || send.body->Option.mapOr(false, uses) || expected(expect)
    | Lose(_) | Wait(_) => false
    }
  )
}

/**
 * What every case begins with captured, the organization `--organization` names, or why the run is
 * refused, naming each case using it where none is named.
 */
let captured = (given: option<string>, ~using: array<string>) =>
  switch given {
  | Some(text) =>
    switch Float.fromString(text) {
    | Some(id) if /^(0|[1-9][0-9]*)$/->RegExp.test(text) && id <= 4294967295. =>
      Ok(Dict.fromArray([(organization, JSON.Number(id))]))
    | Some(_) | None => Error(`--organization ${text}, no id of an organization`)
    }
  | None if using == [] => Ok(dict{})
  | None =>
    Error(
      `--organization is required by the cases using the run's organization: ${using->Array.join(
          "; ",
        )}`,
    )
  }
