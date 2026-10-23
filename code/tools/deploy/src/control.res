module Contracts = Envelope.Contracts

let operatorVariable = "CONTROL_OPERATOR"

let origin = target =>
  switch target->String.startsWith("control:") {
  | false => None
  | true =>
    let given = target->String.slice(~start=String.length("control:"))
    let trimmed = given->String.endsWith("/") ? given->String.slice(~start=0, ~end=-1) : given
    Some(
      /^https?:\/\/[^\/?#]+$/->RegExp.test(trimmed)
        ? Ok(trimmed)
        : Error(`${given} is no control's origin, http or https and no path`),
    )
  }

let gateway = (~origin, ~app) => `${origin}/v1/app-${Float.toString(app)}/`

type t = {
  origin: string,
  operator: string,
  fetch: (string, Web.init) => promise<Web.response>,
}

let named = (envelope, key) =>
  envelope
  ->JSON.Decode.object
  ->Option.flatMap(o => o->Dict.get(key))
  ->Option.flatMap(JSON.Decode.string)
  ->Option.getOr("")

/** A call of the control's API, its output read as its type. */
let call = async (control, envelope, data) =>
  switch await control.fetch(
    `${control.origin}/${named(envelope, "interface")}/${named(envelope, "operation")}`,
    {
      method: "POST",
      headers: dict{
        "authorization": `Bearer ${control.operator}`,
        "content-type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify(envelope),
    },
  ) {
  | exception JsExn(e) =>
    Error(
      (
        {
          reason: "unreached",
          message: `${control.origin} did not answer, ${e->JsExn.message->Option.getOr("")}`,
        }: Machine.refused
      ),
    )
  | response => Machine.answer(await response->Web.text, data)
  }

let releases = call => Contracts.Interface.Releases.toJson({call, capabilities: []})

let put = (control, artifact) =>
  call(control, releases(Put({form: Modules, artifact})), Contracts.ReleaseHeld.fromJson)

let deploy = (control, ~binding, ~app, ~hash) =>
  call(
    control,
    releases(Deploy({binding, app, release: hash})),
    Contracts.DeploymentDescribed.fromJson,
  )

let describe = (control, ~app) =>
  call(control, releases(Describe({app: app})), Contracts.DeploymentDescribed.fromJson)

let asked = async (control, ~app) => {
  let address = gateway(~origin=control.origin, ~app)
  switch await control.fetch(address, {method: "GET", headers: dict{}}) {
  | exception JsExn(e) => Error(`${address} did not answer, ${e->JsExn.message->Option.getOr("")}`)
  | response =>
    let body = await response->Web.text
    response->Web.status == 200
      ? Ok(body->String.trim)
      : Error(`${address} answered ${Int.toString(response->Web.status)}, ${body->String.trim}`)
  }
}
