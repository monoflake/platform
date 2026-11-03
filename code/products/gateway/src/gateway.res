module Web = ControlOrganization.Web
module Ids = ControlOrganization.Ids
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

type routed = {app: float, path: string}

/** A mount's path, its scope written as a label is, RFC vr5lw. */
let scoped = /^\/v[0-9]+\/([a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)(\/.*)?$/

let mounted = async (state: State.reads, ~organization, path) =>
  switch scoped->RegExp.exec(path) {
  | Some(found) =>
    switch found->RegExp.Result.matches {
    | [Some(scope), rest] =>
      (await state.mount(~organization, ~scope))->Option.map(app => {
        app,
        path: rest->Option.getOr("/"),
      })
    | _ => None
    }
  | None => None
  }

let named = async (state: State.reads, host) => {
  let host = host->String.toLowerCase->String.split(":")->Array.get(0)->Option.getOr("")
  switch await state.domain(host) {
  | Some(app) => Some(app)
  | None =>
    switch host->String.indexOf(".") {
    | -1 => None
    | at => await state.domain("*." ++ host->String.slice(~start=at + 1))
    }
  }
}

let host = (~app, ~binding) => `${Ids.text(app)}.b${Ids.text(binding)}`

/** The scope the gateway reserves for its organization's storage, RFC vr5lw. */
let storageScope = "storage"

/** The organization's storage as configured, `{id}.b{binding}`, until a control deploys it. */
let configuredStorage = /^([0-9a-f]{8})\.b([0-9a-f]{1,16})$/

let computed = configured =>
  switch configuredStorage->RegExp.exec(configured) {
  | Some(found) if configured->String.length == 18 =>
    switch found->RegExp.Result.matches {
    | [Some(app), Some(binding)] =>
      switch (Ids.ofText(app), Ids.ofText(binding)) {
      | (Some(app), Some(binding)) => Some((app, binding))
      | _ => None
      }
    | _ => None
    }
  | Some(_) | None => None
  }

let stored = (~configured, path) =>
  switch (scoped->RegExp.exec(path), configuredStorage->RegExp.exec(configured)) {
  | (Some(found), Some(named)) =>
    switch (found->RegExp.Result.matches, named->RegExp.Result.matches) {
    | ([Some(scope), _], [Some(app), Some(binding)]) if scope == storageScope =>
      switch (Ids.ofText(app), Ids.ofText(binding)) {
      | (Some(app), Some(binding)) => Some((app, binding))
      | _ => None
      }
    | _ => None
    }
  | _ => None
  }

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

let reached = async (
  state: State.reads,
  reach: Reach.t,
  ~port,
  request,
  ~app,
  ~binding,
  ~path,
  ~search,
) => {
  let routed: routed = {app, path}
  switch await state.binding(binding) {
  | Some({origin: Some(_)}) =>
    beyondHost(
      `app ${Ids.text(routed.app)} runs on a binding reached by its origin, never through here`,
    )
  | Some({bound: Some(_), address: Some(address)}) =>
    let named = host(~app=routed.app, ~binding)
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

let passed = async (state: State.reads, reach: Reach.t, ~port, request, routed, ~search) =>
  switch await state.deployment(routed.app) {
  | None => Web.answered(~status=404, `no app ${Ids.text(routed.app)} is deployed`)
  | Some(deployment) =>
    await reached(
      state,
      reach,
      ~port,
      request,
      ~app=routed.app,
      ~binding=deployment.binding,
      ~path=routed.path,
      ~search,
    )
  }

let through = async (
  state: State.reads,
  reach: Reach.t,
  ~port,
  request,
  routed,
  ~compute,
  ~search,
) =>
  switch await state.deployment(routed.app) {
  | None => Web.answered(~status=404, `no app ${Ids.text(routed.app)} is deployed`)
  | Some(deployment) =>
    let made = Web.resent(request->Web.url, request)
    made
    ->Web.requestHeaders
    ->Web.setHeader("target", host(~app=routed.app, ~binding=deployment.binding))
    let (app, binding) = compute
    await reached(state, reach, ~port, made, ~app, ~binding, ~path=routed.path, ~search)
  }

/** Every answer guarded, never sniffed and opened sandboxed but a PDF, RFCs vr5lw and 13ixj. */
let guarded = response => {
  let made = Answers.rewrapped(Answers.body(response), response)
  let headers = made->Web.responseHeaders
  headers->Web.setHeader("x-content-type-options", "nosniff")
  let pdf =
    headers
    ->Web.header("content-type")
    ->Nullable.toOption
    ->Option.mapOr(false, kind => kind->String.startsWith("application/pdf"))
  pdf ? () : headers->Web.setHeader("content-security-policy", "sandbox")
  made
}
