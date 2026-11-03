module Ids = Ids.Id

type request = Web.request
type response = Web.response
type records = {execute: JSON.t => promise<JSON.t>}
type database = {status: string => promise<JSON.t>}
type service = {fetch: request => promise<response>}
type env = {
  @as("ENTRY") entry?: string,
  records?: records,
  database?: database,
  @as("STORAGE") storage?: service,
  @as("LIFE") life?: string,
  @as("DEADLINE") deadline?: string,
  @as("RETENTION") retention?: string,
}

let target = text =>
  switch text->String.split(".b") {
  | [app, binding] =>
    switch (Ids.ofText(app), Ids.ofText(binding)) {
    | (Some(app), Some(binding)) => Some((app, binding))
    | (None, _) | (_, None) => None
    }
  | _ => None
  }

let passed = (request, ~entry, ~app, ~binding) => {
  let parts = Web.parts(request->Web.url)
  let sent = Web.resent(`${entry}${parts->Web.pathname}${parts->Web.search}`, request)
  let headers = sent->Web.requestHeaders
  let named = `${Ids.text(app)}.b${Ids.text(binding)}`
  headers->Web.setHeader("host", named)
  headers->Web.setHeader("x-forwarded-host", named)
  headers->Web.deleteHeader("target")
  Web.fetch(sent)
}

let issuer = Calls.issuer()

let bound = value =>
  value->Option.flatMap(text =>
    if /^[0-9]+$/->RegExp.test(text) {
      let number = Float.fromString(text)
      number->Option.filter(number => number > 0. && number <= 9007199254740991.)
    } else {
      None
    }
  )

// The call bounds the author fixed, bundled with this build; env overrides them for tests alone.
type bounds = {idLife: float, lookupDeadline: float, statusRetention: float}
@module({from: "../../../../model/protocol/calls.json", with: {type_: "json"}})
external bounds: bounds = "default"

let refused = (~status=503, reason) => {
  let failure = reason == "unknown" ? Envelope.Contracts.Failure.Unknown : Unavailable
  Web.json(
    ~status,
    JSON.Object(
      dict{
        "Error": Envelope.Contracts.Error.toJson({
          failure,
          reason,
          message: Envelope.Contracts.messages->Dict.get(reason)->Option.getOr(reason),
        }),
      },
    ),
  )
}

let status = async (request, ~execute, ~retention) => {
  try {
    let input = await request->Web.requestJson
    let id =
      input
      ->JSON.Decode.object
      ->Option.flatMap(o => o->Dict.get("id"))
      ->Option.flatMap(JSON.Decode.string)
      ->Option.getOr("")
    switch await Calls.found(~execute, ~id) {
    | Error(_) => refused("unavailable")
    | Ok(record) =>
      let answer = Status.answered(
        ~recorded=record->Option.map(record => (record.expires, record.outcome)),
        ~steps=None,
        ~issued=Calls.issuedAt(id)->Option.getOr(Web.now()),
        ~now=Web.now(),
        ~retention,
      )
      Web.json(~status=200, Status.json(~id, answer))
    }
  } catch {
  | JsExn(_) => Web.answered(~status=400, "the status call needs an id")
  }
}

module Contracts = Envelope.Contracts

let none: Lookup.steps = {committed: [], finished: false}

let known = (steps: Contracts.CallSteps.t): Lookup.steps => {
  committed: steps.committed->Array.map(Float.toInt),
  finished: steps.finished,
}

let fromDatabase = async (database: option<database>, ~id) =>
  switch database {
  | None => Error("the database is not bound")
  | Some(database) =>
    try {
      switch Contracts.CallSteps.fromJson(await database.status(id)) {
      | Ok(steps) => Ok(known(steps))
      | Error(_) => Error("the database answered malformed steps")
      }
    } catch {
    | JsExn(error) if error->JsExn.message->Option.getOr("")->String.startsWith("not_found:") =>
      Ok(none)
    | _ => Error("the database refused the status")
    }
  }

let fromStorage = async (storage: option<service>, ~app, ~id) =>
  switch storage {
  | None => Error("the storage is not bound")
  | Some(storage) =>
    try {
      let asked = Web.request(
        "http://storage/storage/status",
        {
          method: "POST",
          headers: dict{"content-type": "application/json", "caller": Ids.text(app)},
          body: JSON.stringify(JSON.Object(dict{"id": JSON.String(id)})),
        },
      )
      let answer = await storage.fetch(asked)
      switch Contracts.Answer.fromJson(
        await answer->Web.responseJson,
        Contracts.CallSteps.fromJson,
      ) {
      | Ok(Success(steps)) => Ok(known(steps))
      | Ok(Error(error)) if error.reason == "not_found" => Ok(none)
      | Ok(Error(error)) => Error(`the storage answered ${error.reason}`)
      | Error(_) => Error("the storage answered malformed steps")
      }
    } catch {
    | _ => Error("the storage refused the status")
    }
  }

let merged = (one: Lookup.steps, other: Lookup.steps): Lookup.steps => {
  let sorted = one.committed->Array.concat(other.committed)->Array.toSorted(Int.compare)
  {
    committed: sorted->Array.filterWithIndex((sequence, index) =>
      index == 0 || sorted->Array.getUnsafe(index - 1) != sequence
    ),
    finished: one.finished || other.finished,
  }
}

let steps = async (~database, ~storage, ~app, ~id) =>
  switch await Promise.all2((fromDatabase(database, ~id), fromStorage(storage, ~app, ~id))) {
  | (Error(one), Error(other)) => Error(`${one}; ${other}`)
  | (Ok(steps), Error(_)) | (Error(_), Ok(steps)) => Ok(merged(steps, none))
  | (Ok(one), Ok(other)) => Ok(merged(one, other))
  }

let sent = async (
  request,
  ~entry,
  ~app,
  ~binding,
  ~execute,
  ~database,
  ~storage,
  ~life,
  ~deadline,
) => {
  switch Calls.issued(issuer, ~now=Web.now()) {
  | None => refused("unavailable")
  | Some(id) =>
    let expires = Calls.issuedAt(id)->Option.getOr(Web.now()) +. life
    let ready = switch await Calls.made(~execute) {
    | Error(reason) => Error(reason)
    | Ok() =>
      await Calls.recorded(
        ~execute,
        {
          id,
          app,
          function: request->Web.url->Web.parts->Web.pathname,
          expires,
          outcome: None,
        },
      )
    }
    switch ready {
    | Error(_) => refused("unavailable")
    | Ok() =>
      let request = Web.resent(request->Web.url, request)
      request->Web.requestHeaders->Web.setHeader("Call", id)
      let (answer, heard) = try {
        let answer = await passed(request, ~entry, ~app, ~binding)
        let contentType =
          answer
          ->Web.responseHeaders
          ->Web.header("content-type")
          ->Nullable.toOption
          ->Option.getOr("")
          ->String.toLowerCase
        let failure = if contentType->String.includes("application/json") {
          try {
            Outcome.failureOf(await answer->Web.clone->Web.responseJson)
          } catch {
          | JsExn(_) => None
          }
        } else {
          None
        }
        (Some(answer), Outcome.Answered({status: answer->Web.status, failure}))
      } catch {
      | JsExn(_) => (None, Outcome.Lost)
      }
      let (outcome, answer) = switch Outcome.classified(heard) {
      | Told(outcome) => (outcome, answer->Option.getOr(refused("unavailable")))
      | Look =>
        let (found, _looked) = await Lookup.looked(
          ~steps=() => steps(~database, ~storage, ~app, ~id),
          ~expires,
          ~deadline,
          ~now=Web.now,
          ~wait=Web.wait,
        )
        switch found {
        | Finished => (Outcome.Success, Web.json(~status=200, JSON.Object(dict{"Ok": JSON.Null})))
        | NotSeen => (Outcome.Unavailable, refused("unavailable"))
        | Open(_) => (
            Outcome.Unknown,
            // The id travels in `Call`; the error's `call` waits on the author's answer.
            refused("unknown"),
          )
        }
      }
      let _ = await Calls.told(~execute, ~id, ~outcome=Outcome.name(outcome))
      Web.withCall(answer, id)
    }
  }
}

let fetch = async (request, env) => {
  let given = (text, fixed) => text->Option.isSome ? bound(text) : Some(fixed)
  switch (
    env.entry,
    env.records,
    given(env.life, bounds.idLife),
    given(env.deadline, bounds.lookupDeadline),
    given(env.retention, bounds.statusRetention),
  ) {
  | (Some(entry), Some(records), Some(life), Some(deadline), Some(retention)) =>
    if (
      request->Web.method_ == "POST" &&
        request->Web.url->Web.parts->Web.pathname == "/compute/status"
    ) {
      await status(request, ~execute=records.execute, ~retention)
    } else {
      switch request
      ->Web.requestHeaders
      ->Web.header("target")
      ->Nullable.toOption
      ->Option.flatMap(target) {
      | None => Web.answered(~status=400, "the call names no target")
      | Some((app, binding)) =>
        await sent(
          request,
          ~entry,
          ~app,
          ~binding,
          ~execute=records.execute,
          ~database=env.database,
          ~storage=env.storage,
          ~life,
          ~deadline,
        )
      }
    }
  | _ =>
    Web.answered(~status=500, "compute is missing a required binding or positive integer bound")
  }
}

type worker = {fetch: (request, env) => promise<response>}
let default = {fetch: fetch}
