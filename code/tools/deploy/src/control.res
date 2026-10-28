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

let gateway = ingress =>
  ingress
  ->Option.getOr([])
  ->Array.findMap((i: Contracts.AppIngress.t) =>
    switch i {
    | Domain({domain}) if !(domain->String.startsWith("*.")) => Some("https://" ++ domain ++ "/")
    | Domain(_) | Mount(_) | Binding => None
    }
  )

let declared = (~app, ~binding, ingress) => {
  let items =
    ingress
    ->Option.getOr([])
    ->Array.map((i: Contracts.AppIngress.t) =>
      switch i {
      | Domain({domain}) => "domain " ++ domain
      | Mount({scope}) => "mount " ++ scope
      | Binding => `binding ${Ids.Id.text(app)}.b${Ids.Id.text(binding)}`
      }
    )
  "declared ingress " ++ (items == [] ? "none" : items->Array.join(", "))
}

let messages = (~ingress, ~app, ~binding) => [
  "deploy: app " ++ Ids.Id.text(app),
  "deploy: " ++ declared(~app, ~binding, ingress),
  switch gateway(ingress) {
  | Some(url) => "deploy: open " ++ url
  | None => "deploy: no direct domain to probe, nothing probed"
  },
]

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

let put = (control, ~kinds=?, ~ingress=?, artifact) =>
  call(
    control,
    releases(Put({form: Modules, artifact, ?kinds, ?ingress})),
    Contracts.ReleaseHeld.fromJson,
  )

let deploy = (control, ~binding, ~app, ~hash, ~secrets, ~network) =>
  call(
    control,
    releases(
      Deploy({
        binding,
        ?app,
        release: hash,
        secrets: ?(secrets->Dict.keysToArray == [] ? None : Some(secrets)),
        network: ?(network == [] ? None : Some(network)),
      }),
    ),
    Contracts.DeploymentDescribed.fromJson,
  )

let forget = (control, ~app) =>
  call(control, releases(Forget({app: app})), Contracts.ReleaseOf.fromJson)

let retire = (control, ~app) =>
  call(control, releases(Retire({app: app})), Contracts.ReleaseOf.fromJson)

let describe = (control, ~app) =>
  call(control, releases(Describe({app: app})), Contracts.DeploymentDescribed.fromJson)

let asked = async (control, ~ingress) =>
  switch gateway(ingress) {
  | None => Ok("no direct domain to probe, nothing probed")
  | Some(address) =>
    switch await control.fetch(address, {method: "GET", headers: dict{}}) {
    | exception JsExn(e) =>
      Error(`${address} did not answer, ${e->JsExn.message->Option.getOr("")}`)
    | response =>
      let body = await response->Web.text
      let status = response->Web.status
      let first = body->String.trim->String.split("\n")->Array.get(0)->Option.getOr("")
      // A gateway failure cannot establish that the app answered.
      [502, 503, 504]->Array.includes(status)
        ? Error(`${address} answered ${Int.toString(status)}, ${body->String.trim}`)
        : Ok(`${Int.toString(status)}, ${first}`)
    }
  }
