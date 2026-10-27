module Web = ControlOrganization.Web
module Ids = ControlOrganization.Ids
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

type routed = {app: float, path: string}

/** A scope of an app until an organization's own scopes are kept, RFC vr5lw's `scope` rows. */
let scoped = /^\/v[0-9]+\/([0-9a-f]{8})(\/.*)?$/

// A scaffold for ids deployed before they were drawn in hex, retired with B at RFC 8yl4b.
let decimal = /^\/v[0-9]+\/app-([1-9][0-9]{0,9})(\/.*)?$/

/** The id and the rest a pattern found, the id read by `read`. */
let found = (pattern, path, read) =>
  switch pattern->RegExp.exec(path) {
  | Some(found) =>
    switch found->RegExp.Result.matches {
    | [Some(id), rest] => read(id)->Option.map(app => {app, path: rest->Option.getOr("/")})
    | _ => None
    }
  | None => None
  }

let routed = path =>
  switch found(scoped, path, Ids.ofText) {
  | Some(routed) => Some(routed)
  | None => found(decimal, path, id => Float.fromString(id)->Option.filter(id => id <= 4294967295.))
  }

let host = (~app, ~binding) => `${Ids.text(app)}.b${Ids.text(binding)}`

/** Whether a request can be sent again, its body none that a first send would have spent. */
let resendable = request =>
  switch request->Web.method_ {
  | "GET" | "HEAD" | "OPTIONS" => true
  | _ => request->Web.requestBody->Nullable.isNullable
  }

/** What answers for a binding reached by its origin, whose data never passes here, 8j7b0. */
let beyondHost = message =>
  Web.answered(
    ~status=400,
    ~contentType="application/json",
    Envelope.Contracts.Answer.toJson(
      Error({failure: Rejected, reason: "beyond_host", message}),
      _ => JSON.Null,
    )->JSON.stringify,
  )

let passed = async (state: State.reads, reach: Reach.t, ~port, request, routed, ~search) =>
  switch await state.deployment(routed.app) {
  | None => Web.answered(~status=404, `no app ${Ids.text(routed.app)} is deployed`)
  | Some(deployment) =>
    switch await state.binding(deployment.binding) {
    | Some({origin: Some(_)}) =>
      beyondHost(
        `app ${Ids.text(routed.app)} runs on a binding reached by its origin, never through here`,
      )
    | Some({bound: Some(_), address: Some(address)}) =>
      let named = host(~app=routed.app, ~binding=deployment.binding)
      let sent = () => {
        let made = Web.resent(`${reach.origin(~address, ~port)}${routed.path}${search}`, request)
        // workerd sends the URL's host whatever `Host` says, so the name travels beside it too.
        made->Web.requestHeaders->Web.setHeader("host", named)
        made->Web.requestHeaders->Web.setHeader("x-forwarded-host", named)
        made
      }
      let unanswered = e => {
        let why = e->JsExn.message->Option.getOr("no message")
        Console.error(`gateway: app ${Ids.text(routed.app)}, ${why}`)
        Web.answered(
          ~status=503,
          `the host running app ${Ids.text(routed.app)} did not answer, ${why}`,
        )
      }
      switch await reach.fetch(sent()) {
      | answer => answer
      // A connection the entry closed as it restarted fails before any answer, so a request with
      // no body to spend is sent once more, on a connection opened anew.
      | exception JsExn(_) if resendable(request) =>
        switch await reach.fetch(sent()) {
        | answer => answer
        | exception JsExn(e) => unanswered(e)
        }
      | exception JsExn(e) => unanswered(e)
      }
    | Some({bound: None}) | Some({address: None}) | None =>
      Web.answered(~status=503, `the host of app ${Ids.text(routed.app)} is not bound`)
    }
  }
