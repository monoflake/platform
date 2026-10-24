/***
 * A target's sends made as the host component makes a call, RFCs b8f35 and p8e8k.
 */
module Contracts = Envelope.Contracts

let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

let running = json =>
  switch (
    field(json, "runs"),
    field(json, "state")
    ->Option.flatMap(s => field(s, "address"))
    ->Option.flatMap(JSON.Decode.string),
  ) {
  | (Some(runs), Some(address)) => Some((address, runs))
  | (Some(_) | None, Some(_) | None) => None
  }

/** What the target answered a describe as the host's driver reads it, an answer of its contract. */
let answerOf = (answered: Run.answered) =>
  Contracts.Answer.fromJson(
    switch answered {
    | Answered(data) => JSON.Object(dict{"status": JSON.String("success"), "data": data})
    | Failed({failure, reason, message}) =>
      JSON.Object(
        dict{
          "status": JSON.String("error"),
          "failure": JSON.String(failure),
          "reason": JSON.String(reason),
          "message": JSON.String(message),
        },
      )
    },
    Contracts.DeploymentDescribed.fromJson,
  )

let target = (target: Run.target, ~post) => {
  let deployed = Dict.make()
  let call = async (~interface, ~operation, ~input, ~form, ~as_) => {
    let answered = await target.call(~interface, ~operation, ~input, ~form, ~as_)
    switch (interface, answered) {
    | ("deployments", Ok(Run.Answered(json))) =>
      running(json)->Option.forEach(((address, runs)) => deployed->Dict.set(address, runs))
    | (_, Ok(Answered(_) | Failed(_)) | Error(_)) => ()
    }
    answered
  }
  let send = async (~to, ~export, ~key, ~body, ~form) =>
    switch deployed->Dict.get(to)->Option.map(Contracts.DeploymentRuns.fromJson) {
    | None | Some(Error(_)) => Error(`no deployment the run was answered running at ${to}`)
    | Some(Ok(runs)) =>
      let driver: Host.Handed.driver = {
        describe: async of_ =>
          switch await target.call(
            ~interface="deployments",
            ~operation="describe",
            ~input=Contracts.DeploymentOf.toJson(of_),
            ~form,
            ~as_=None,
          ) {
          | Ok(answered) =>
            switch answerOf(answered) {
            | Ok(answer) => answer
            | Error({expected}) =>
              Error({failure: Unknown, reason: "fault", message: `describe answered ${expected}`})
            }
          | Error(why) => Error({failure: Unknown, reason: "fault", message: why})
          },
      }
      let request: Host.Handed.request = {
        contentType: Some("application/json"),
        accept: Some("application/json"),
        body: body->Option.mapOr(Uint8Array.fromLength(0), b => Web.utf8(JSON.stringify(b))),
      }
      // A state the host leaves for later, C44, throws, and is no answer.
      switch await Host.Handed.call(driver, ~post, {runs, export, key, request}) {
      | Answered({status, body}) => Ok(Http.sent(status, body))
      | Refused({failure, reason, message}) =>
        Ok(Run.Failed({failure: (failure :> string), reason, message}))
      | exception JsExn(e) => Error(e->JsExn.message->Option.getOr("the host refused the call"))
      }
    }
  {...target, call, send}
}
