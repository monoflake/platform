module Web = ControlOrganization.Web
module Ids = ControlOrganization.Ids
module Stores = ControlOrganization.Stores
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

let reachOf = Reach.configured

let fetch = async (request, env: Stores.env) =>
  switch (env.state->Option.map(State.readsOfDatabase), reachOf(env)) {
  | (Some(state), Some(reach)) =>
    let located = Web.parts(request->Web.url)
    let host =
      request
      ->Web.requestHeaders
      ->Web.header("host")
      ->Nullable.toOption
      ->Option.getOr(located->Web.hostname)
    let path = located->Web.pathname
    let routed = switch await Gateway.named(state, host) {
    | Some(app) => Ok(Some(({app, path}: Gateway.routed)))
    | None =>
      switch env.organization->Option.flatMap(Ids.ofText) {
      | Some(organization) => Ok(await Gateway.mounted(state, ~organization, path))
      | None => Error()
      }
    }
    switch routed {
    | Error() => Web.answered(~status=500, "the gateway's ORGANIZATION names no organization")
    | Ok(None) => Web.answered(~status=404, "not found")
    | Ok(Some(routed)) =>
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
    }
  | _ => Web.answered(~status=500, "the gateway has no state database or host reach")
  }

type worker = {fetch: (Web.request, Stores.env) => promise<Web.response>}

let default: worker = {fetch: fetch}
