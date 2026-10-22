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

let refused = (failure, reason): answer => Refused({
  failure,
  reason,
  message: Contracts.messages->Dict.get(reason)->Option.getOr(""),
})

let url = (address, export, key) =>
  switch key {
  | None => Some(`${address}/${export}`)
  | Some(key) if plain->RegExp.test(key) => Some(`${address}/${key}/${export}`)
  | Some(_) => None
  }

let call = async (driver, ~post: post, call) =>
  switch await driver.describe({runs: call.runs}) {
  | Error(error) => Refused(error)
  | Success({state: Running({address})}) =>
    switch url(address, call.export, call.key) {
    | Some(url) =>
      switch await post(url, call.request) {
      | Ok(response) => Answered(response)
      | Error(error) => Refused(error)
      }
    | None => %todo("C44")
    }
  | Success({state: Stopped}) => refused(Unavailable, "stopped")
  | Success({state: Making | Failed(_)}) => %todo("C44")
  }
