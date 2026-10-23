type routed = {app: float, path: string}

/** A scope of an app until an organization's own scopes are kept, RFC vr5lw's `scope` rows. */
let scoped = /^\/v[0-9]+\/app-([1-9][0-9]{0,9})(\/.*)?$/

let routed = path =>
  switch scoped->RegExp.exec(path) {
  | Some(found) =>
    switch found->RegExp.Result.matches {
    | [Some(id), rest] =>
      Float.fromString(id)
      ->Option.filter(id => id <= 4294967295.)
      ->Option.map(app => {app, path: rest->Option.getOr("/")})
    | _ => None
    }
  | None => None
  }

let host = (~app, ~binding) => `app-${Float.toString(app)}.b${Float.toString(binding)}`

let passed = async (state: State.t, reach: Reach.t, ~port, request, routed, ~search) =>
  switch await state.deployment(routed.app) {
  | None => Web.answered(~status=404, `no app ${Float.toString(routed.app)} is deployed`)
  | Some(deployment) =>
    switch await state.binding(deployment.binding) {
    | Some({address: Some(address)}) =>
      let sent = Web.resent(`${reach.origin(~address, ~port)}${routed.path}${search}`, request)
      let named = host(~app=routed.app, ~binding=deployment.binding)
      // workerd sends the URL's host whatever `Host` is set to, so the name travels beside it too.
      sent->Web.requestHeaders->Web.setHeader("host", named)
      sent->Web.requestHeaders->Web.setHeader("x-forwarded-host", named)
      switch await reach.fetch(sent) {
      | exception JsExn(_) =>
        Web.answered(
          ~status=503,
          `the host running app ${Float.toString(routed.app)} did not answer`,
        )
      | answer => answer
      }
    | Some({address: None}) | None =>
      Web.answered(~status=503, `the host of app ${Float.toString(routed.app)} is not bound`)
    }
  }
