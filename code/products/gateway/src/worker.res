module Web = ControlOrganization.Web
module Stores = ControlOrganization.Stores
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

let reachOf = Reach.configured

let fetch = async (request, env: Stores.env) => {
  let located = Web.parts(request->Web.url)
  switch Gateway.routed(located->Web.pathname) {
  | None => Web.answered(~status=404, "not found")
  | Some(routed) =>
    switch (env.state, reachOf(env)) {
    | (Some(database), Some(reach)) =>
      await Gateway.passed(
        State.readsOfDatabase(database),
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
