/*** A call handed to the deployment that runs it, RFCs vr5lw and b8f35. */
module Contracts = Envelope.Contracts

type driver = {
  describe: Contracts.DeploymentOf.t => promise<
    Contracts.Answer.t<Contracts.DeploymentDescribed.t>,
  >,
}

type request = {contentType: option<string>, accept: option<string>, body: Uint8Array.t}

type response = {status: int, contentType: option<string>, body: Uint8Array.t}

type post = (string, request) => promise<result<response, Contracts.Error.t>>

type call = {
  runs: Contracts.DeploymentRuns.t,
  export: string,
  key: option<string>,
  request: request,
}

type answer = Answered(response) | Refused(Contracts.Error.t)

/** A key a path segment holds as it is, RFC 3986's unreserved characters, RFC tkil2. */
let plain = /^[A-Za-z0-9._~-]+$/

/** A kebab-case label as wit* reads one, its `Lexer.label`. */
let label = "([a-z][0-9a-z]*|[A-Z][0-9A-Z]*)(-([0-9a-z]+|[0-9A-Z]+))*"

/** A function by the name a call gives it, `{function}` or `{interface}.{function}`. */
let function = RegExp.fromString(`^(${label}\\.)?${label}$`)

let refused = (failure, reason): answer => Refused({
  failure,
  reason,
  message: Contracts.messages->Dict.get(reason)->Option.getOr(""),
})

/** A call naming no function, or a key a path resolves away, so a URL would leave its address. */
let malformed = call =>
  !(function->RegExp.test(call.export)) || call.key == Some(".") || call.key == Some("..")

let url = (address, export, key) =>
  switch key {
  | None => Some(`${address}/${export}`)
  | Some(key) if plain->RegExp.test(key) => Some(`${address}/${key}/${export}`)
  | Some(_) => None
  }

let call = async (driver, ~post: post, call) =>
  switch malformed(call) ? None : Some(await driver.describe({runs: call.runs})) {
  | None => refused(Rejected, "malformed")
  | Some(Error(error)) => Refused(error)
  // An answer for another deployment than the one asked is the driver's fault, RFC ge55b.
  | Some(Success({runs})) if runs != call.runs => refused(Unknown, "fault")
  | Some(Success({state: Running({address})})) =>
    switch url(address, call.export, call.key) {
    | Some(url) =>
      switch await post(url, call.request) {
      | Ok(response) => Answered(response)
      | Error(error) => Refused(error)
      }
    | None => %todo("C44")
    }
  | Some(Success({state: Stopped})) => refused(Unavailable, "stopped")
  | Some(Success({state: Making | Failed(_)})) => %todo("C44")
  }
