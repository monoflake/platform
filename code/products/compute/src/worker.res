module Ids = Ids.Id

type request = Web.request
type response = Web.response
type records = {execute: JSON.t => promise<JSON.t>}
type env = {
  @as("ENTRY") entry?: string,
  records?: records,
}

let target = text =>
  switch text->String.split(".b") {
  | [app, binding] =>
    switch (Ids.ofText(app), Ids.ofText(binding)) {
    | (Some(app), Some(binding)) => Some((app, binding))
    | (None, _) | (_, None) => None
    }
  | _ => None
  }

let passed = (request, ~entry, ~app, ~binding) => {
  let parts = Web.parts(request->Web.url)
  let sent = Web.resent(`${entry}${parts->Web.pathname}${parts->Web.search}`, request)
  let headers = sent->Web.requestHeaders
  let named = `${Ids.text(app)}.b${Ids.text(binding)}`
  headers->Web.setHeader("host", named)
  headers->Web.setHeader("x-forwarded-host", named)
  headers->Web.deleteHeader("target")
  Web.fetch(sent)
}

let fetch = async (request, env) => {
  let named =
    request->Web.requestHeaders->Web.header("target")->Nullable.toOption->Option.flatMap(target)
  switch (named, env.entry) {
  | (None, _) => Web.answered(~status=400, "the call names no target")
  | (Some(_), None) => Web.answered(~status=500, "compute has no ENTRY")
  | (Some((app, binding)), Some(entry)) =>
    try await passed(request, ~entry, ~app, ~binding) catch {
    | JsExn(error) =>
      let why = error->JsExn.message->Option.getOr("no message")
      Console.error(`compute: app ${Ids.text(app)}, ${why}`)
      Web.answered(~status=503, `the host running app ${Ids.text(app)} did not answer, ${why}`)
    }
  }
}

type worker = {fetch: (request, env) => promise<response>}
let default = {fetch: fetch}
