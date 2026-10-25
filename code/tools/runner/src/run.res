/***
 * A behavior file run against an implementation through a target, RFC p8e8k.
 */
type form = Cbor | Json

type answered = Answered(JSON.t) | Failed({failure: string, reason: string, message: string})

type fixture = {form: string, address: string, hash: string, architecture: option<string>}

type target = {
  call: (
    ~interface: string,
    ~operation: string,
    ~input: JSON.t,
    ~form: form,
    ~as_: option<string>,
    ~bearer: option<string>,
  ) => promise<result<answered, string>>,
  send: (
    ~to: string,
    ~export: string,
    ~key: option<string>,
    ~body: option<JSON.t>,
    ~form: form,
  ) => promise<result<answered, string>>,
  given: (
    ~interface: string,
    ~form: form,
    option<JSON.t>,
  ) => promise<result<unit, Filling.unfilled>>,
  lose: int => promise<result<unit, Filling.unfilled>>,
  bound: string => option<float>,
  fixture: string => result<fixture, string>,
  signed: Matching.signed,
  now: unit => float,
  wait: int => promise<unit>,
  network: bool,
  tunnel: bool,
  captured: Matching.captures,
}

type outcome =
  | Passed
  | Failed({step: int, why: string})
  | Skipped(string)

type result_ = {description: string, outcomes: array<(form, outcome)>}

/** How `within` is retried, first after 100 ms and doubling to at most 2 s between tries. */
let firstDelay = 100
let longestDelay = 2000

/** Why a case was skipped, what the target does not offer, which p8e8k leaves for later. */
let unoffered = what => `${what}: not offered by this target, left for later by RFC p8e8k`

/** How a step ended, going on with what it captured or ending the case. */
type ended = On(Matching.captures) | Ended(outcome)

let showAnswered = (answered: result<answered, string>) =>
  switch answered {
  | Ok(Answered(json)) => JSON.stringify(json)
  | Ok(Failed({failure, reason, message})) => `${failure} ${reason} (${message})`
  | Error(why) => `nothing: ${why}`
  }

/** The captures with what the answer added, or why it is not as expected. */
let held = (expect: Sample.expect, answered, ~signed, captures) =>
  switch (expect, answered) {
  | (Output(expected) | Answer(expected), Ok(Answered(json))) =>
    switch Matching.matches(~expected, ~answered=json, ~signed, captures) {
    | Ok(captures) => Ok(captures)
    | Error({at, expected, answered}) =>
      Error(`at ${at == "" ? "the answer" : at}, expected ${expected}, answered ${answered}`)
    }
  | (Failure({failure, reason}), Ok(Failed(given)))
    if given.failure == failure && given.reason == reason =>
    Ok(captures)
  | (Output(_) | Answer(_), Ok(Failed(_)) | Error(_)) =>
    Error(`expected an answer, answered ${showAnswered(answered)}`)
  | (Failure({failure, reason}), Ok(Answered(_) | Failed(_)) | Error(_)) =>
    Error(`expected ${failure} ${reason}, answered ${showAnswered(answered)}`)
  }

/**
 * A step's attempt made until it is answered as expected or, `within` some time, its time is past.
 */
let attempted = async (target, ~within, attempt, expect, captures) => {
  let start = target.now()
  let rec go = async (tries, delay) => {
    let answered = await attempt()
    switch held(expect, answered, ~signed=target.signed, captures) {
    | Ok(captures) => Ok(captures)
    | Error(why) =>
      let left = Int.toFloat(within) -. (target.now() -. start)
      if left <= 0. {
        Error(
          within == 0
            ? why
            : `${why}, after ${Int.toString(tries)} tries within ${Int.toString(within)} ms`,
        )
      } else {
        await target.wait(Math.Int.min(delay, Float.toInt(Math.ceil(left))))
        await go(tries + 1, Math.Int.min(delay * 2, longestDelay))
      }
    }
  }
  await go(1, firstDelay)
}

let refusedOf = (unfilled: Filling.unfilled, step) =>
  switch unfilled {
  | Unoffered(what) => Ended(Skipped(unoffered(what)))
  | Unwritten(why) => Ended(Failed({step, why}))
  }

/** A fixture's version, form and artifact written where a step names it, as the check does. */
let withFixture = (input, fixture: fixture) => {
  let fields = input->JSON.Decode.object->Option.mapOr(Dict.make(), Dict.copy)
  let artifact = dict{"address": JSON.String(fixture.address), "hash": JSON.String(fixture.hash)}
  fixture.architecture->Option.forEach(a => artifact->Dict.set("architecture", JSON.String(a)))
  [
    ("version", JSON.String(fixture.hash)),
    ("form", JSON.String(fixture.form)),
    ("artifact", JSON.Object(artifact)),
  ]->Array.forEach(((key, value)) =>
    if fields->Dict.get(key) == None {
      fields->Dict.set(key, value)
    }
  )
  JSON.Object(fields)
}

/** Why a case needing the network is not run, as p8e8k reports it. */
let offline = "needs the network, which this run does not reach, so it is skipped and never passed"

/** The token a capture of `open`'s answer forms, `<binding>.<secret>`, RFC 3d3nt. */
let tokenOf = (captures: Matching.captures, name) =>
  switch captures->Dict.get(name) {
  | None => Error(`the bearer ${name}, captured by no step before`)
  | Some(captured) =>
    let field = key => captured->JSON.Decode.object->Option.flatMap(o => o->Dict.get(key))
    switch (
      field("binding")->Option.flatMap(JSON.Decode.float),
      field("secret")->Option.flatMap(JSON.Decode.string),
    ) {
    | (Some(binding), Some(secret)) => Ok(`${Float.toString(binding)}.${secret}`)
    | _ =>
      Error(`the bearer ${name}, captured as ${JSON.stringify(captured)} and no binding's token`)
    }
  }

let step = async (target, file: Sample.file, case: Sample.case, form, captures, k, step) => {
  let context: Filling.context = {
    description: case.description,
    step: k,
    captures,
    now: target.now(),
    bound: target.bound,
    fixture: name => target.fixture(name)->Result.mapOr(None, f => Some(f.hash)),
  }
  let finish = result =>
    switch result {
    | Ok(captures) => On(captures)
    | Error(why) => Ended(Failed({step: k, why}))
    }
  switch (step: Sample.step) {
  | Call({operation, input, expect, within, as_, bearer, fixture}) =>
    let input = switch fixture {
    | None => Ok(input)
    | Some(name) =>
      switch target.fixture(name) {
      | Ok(fixture) => Ok(withFixture(input, fixture))
      | Error(why) => Error(Filling.Unoffered(`the fixture ${name}, ${why}`))
      }
    }
    let token = switch bearer {
    | None => Ok(None)
    | Some(name) => tokenOf(captures, name)->Result.map(token => Some(token))
    }
    switch (input->Result.flatMap(input => Filling.fill(input, context)), token) {
    | (Error(unfilled), _) => refusedOf(unfilled, k)
    | (Ok(_), Error(why)) => Ended(Failed({step: k, why}))
    | (Ok(input), Ok(bearer)) =>
      let attempt = () =>
        target.call(~interface=file.interface, ~operation, ~input, ~form, ~as_, ~bearer)
      finish(await attempted(target, ~within=within->Option.getOr(0), attempt, expect, captures))
    }
  | Send({send, expect, within}) =>
    switch (
      Filling.fill(send.to, context),
      send.body->Option.mapOr(Ok(None), body =>
        Filling.fill(body, context)->Result.map(b => Some(b))
      ),
    ) {
    | (Error(unfilled), _) | (_, Error(unfilled)) => refusedOf(unfilled, k)
    | (Ok(to), Ok(body)) =>
      switch to->JSON.Decode.string {
      | None => Ended(Failed({step: k, why: `a send to ${JSON.stringify(to)}, no address`}))
      | Some(to) =>
        let attempt = () => target.send(~to, ~export=send.export, ~key=send.key, ~body, ~form)
        finish(await attempted(target, ~within=within->Option.getOr(0), attempt, expect, captures))
      }
    }
  | Lose(copies) =>
    switch await target.lose(copies) {
    | Ok() => On(captures)
    | Error(unfilled) => refusedOf(unfilled, k)
    }
  | Wait(ms) =>
    await target.wait(ms)
    On(captures)
  }
}

/** A case run from what it is given, in one form. */
let fromGiven = async (target, file: Sample.file, case: Sample.case, form) => {
  switch await target.given(~interface=file.interface, ~form, case.given) {
  | Error(Unoffered(what)) => Skipped(unoffered(what))
  | Error(Unwritten(why)) => Failed({step: 0, why: `given before its first step: ${why}`})
  | Ok() =>
    let rec go = async (k, captures) =>
      switch case.steps->Array.get(k) {
      | None => Passed
      | Some(next) =>
        switch await step(target, file, case, form, captures, k, next) {
        | On(captures) => await go(k + 1, captures)
        | Ended(outcome) => outcome
        }
      }
    await go(0, target.captured->Dict.copy)
  }
}

/** Why a case binding by a tunnel is not run, as `offline` says of the network. */
let untunneled = "binds by a tunnel, which this run does not, so it is skipped and never passed"

/** A case run from nothing in one form, skipped where it needs what the run lacks. */
let case = (target, file, case: Sample.case, form) =>
  switch (case.network && !target.network, case.tunnel && !target.tunnel) {
  | (true, _) => Promise.resolve(Skipped(offline))
  | (false, true) => Promise.resolve(Skipped(untunneled))
  | (false, false) => fromGiven(target, file, case, form)
  }

let file = async (file: Sample.file, target) => {
  let rec go = async (n, results) =>
    switch file.cases->Array.get(n) {
    | None => results
    | Some(c) =>
      let cbor = await case(target, file, c, Cbor)
      let json = await case(target, file, c, Json)
      await go(
        n + 1,
        results->Array.concat([
          {description: c.description, outcomes: [(Cbor, cbor), (Json, json)]},
        ]),
      )
    }
  await go(0, [])
}
