module Web = ControlOrganization.Web
module Stores = ControlOrganization.Stores
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

let reachOf = Reach.configured

let fetch = async (request, env: Stores.env) => {
  let located = Web.parts(request->Web.url)
  let state = env.state->Option.map(State.readsOfDatabase)
  let domain = switch state {
  | Some(state) =>
    let host =
      request
      ->Web.requestHeaders
      ->Web.header("host")
      ->Nullable.toOption
      ->Option.getOr(located->Web.hostname)
    await Gateway.named(state, host)
  | None => None
  }
  let routed = switch domain {
  | Some(app) => Some(({app, path: located->Web.pathname}: Gateway.routed))
  | None => Gateway.routed(located->Web.pathname)
  }
  switch routed {
  | None => Web.answered(~status=404, "not found")
  | Some(routed) =>
    switch (state, reachOf(env)) {
    | (Some(state), Some(reach)) =>
      await Gateway.passed(
        state,
        reach,
        ~port=env.entryPort
        ->Option.flatMap(text => Int.fromString(text))
        ->Option.getOr(Reach.entryPort),
        request,
        routed,
        ~search=located->Web.search,
      )
    | _ => Web.answered(~status=500, "the gateway has no state database or host reach")
    }
  }
}

type worker = {fetch: (Web.request, Stores.env) => promise<Web.response>}

let default: worker = {fetch: fetch}
