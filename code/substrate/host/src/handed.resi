/***
 * A call handed to the deployment that runs it, at the address its driver describes, RFCs vr5lw and
 * b8f35. The model's interface, `docs/code.md`.
 */
module Contracts = Envelope.Contracts

/** The host's driver, by the one operation of `deployments` a call needs. */
type driver = {
  describe: Contracts.DeploymentOf.t => promise<
    Contracts.Answer.t<Contracts.DeploymentDescribed.t>,
  >,
}

/** A request or an answer as it came, its `Content-Type`, `Accept` and body carried unread. */
type request = {contentType: option<string>, accept: option<string>, body: Uint8Array.t}

type response = {status: int, contentType: option<string>, body: Uint8Array.t}

/** A request sent by `POST` to a URL, answered, or refused where nothing answers. */
type post = (string, request) => promise<result<response, Contracts.Error.t>>

/** A call of an export of what a deployment runs, for an instance by its key. */
type call = {
  runs: Contracts.DeploymentRuns.t,
  export: string,
  key: option<string>,
  request: request,
}

/** What a call came to, the deployment's answer as it came or a refusal. */
type answer = Answered(response) | Refused(Contracts.Error.t)

/**
 * Posted to `{address}/{export}` or `{address}/{key}/{export}`, refused `malformed` first where
 * either is no plain segment, other `runs` answered `fault` and a stopped one `unavailable`.
 */
let call: (driver, ~post: post, call) => promise<answer>
