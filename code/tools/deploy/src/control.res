module Contracts = Envelope.Contracts

let operatorVariable = "CONTROL_OPERATOR"

let origin = target =>
  switch target->String.startsWith("control:") {
  | false => None
  | true =>
    let given = target->String.slice(~start=String.length("control:"))
    let trimmed = given->String.endsWith("/") ? given->String.slice(~start=0, ~end=-1) : given
    Some(
      /^https?:\/\/[^\/?#]+(\/[^?#]*)?$/->RegExp.test(trimmed)
        ? Ok(trimmed)
        : Error(`${given} is no control's address, http or https with no query`),
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

let deploy = (control, ~binding, ~app, ~hash, ~secrets, ~network) =>
  call(
    control,
    releases(
      Deploy({
        binding,
        app,
        release: hash,
        secrets: ?(secrets->Dict.keysToArray == [] ? None : Some(secrets)),
        network: ?(network == [] ? None : Some(network)),
      }),
    ),
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
    let status = response->Web.status
    let first = body->String.trim->String.split("\n")->Array.get(0)->Option.getOr("")
    // Any answer is the app serving, a control refusing `/` among them, but a gateway's 502 to 504.
    [502, 503, 504]->Array.includes(status)
      ? Error(`${address} answered ${Int.toString(status)}, ${body->String.trim}`)
      : Ok(`${Int.toString(status)}, ${first}`)
  }
}
