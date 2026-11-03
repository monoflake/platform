module Contracts = Envelope.Contracts

let fileName = hash => `${Envelope.Hex.encode(hash)}.tar`

let address = (~directory, ~hash) => `file://${directory}/${fileName(hash)}`

let deploy = (~app, ~hash, ~address, ~into, ~bindings=?): Contracts.DeploymentDeploy.t => {
  runs: App({id: app}),
  version: hash,
  form: Modules,
  isolation: [Isolate],
  artifact: {address, hash},
  // No footing is built yet, so the address is one that answers nothing.
  footing: "https://footing.invalid",
  secrets: dict{},
  network: [],
  into,
  ?bindings,
}

let bindings = (slots: array<Contracts.ManifestSlot.t>, ~database) => {
  let databases = slots->Array.filter(s => s.type_ == Database)
  switch databases {
  | [] => None
  | _ =>
    let filled = Dict.make()
    databases->Array.forEach(s => filled->Dict.set(s.name, database))
    Some(({database: filled}: Contracts.AppBindings.t))
  }
}

let of_ = (app): Contracts.DeploymentOf.t => {runs: App({id: app})}

let host = (~app, ~binding) => `${Ids.Id.text(app)}.b${Ids.Id.text(binding)}`

type progress = Running | Waiting | Elsewhere | Failed(string)

let progress = (described: Contracts.DeploymentDescribed.t, version) =>
  if Envelope.Hex.encode(described.version) != Envelope.Hex.encode(version) {
    Elsewhere
  } else {
    switch described.state {
    | Running(_) => Running
    | Making => Waiting
    | Stopped => Failed("stopped, as deployments stop left it")
    | Failed({reason, ?message}) => Failed(message->Option.mapOr(reason, m => `${reason}, ${m}`))
    }
  }

/** An archive held on the machine only while a deployment is made of it, kept if that fails. */
let held = async (~copy, ~deploy, ~remove) =>
  switch await copy() {
  | Error(why) => Error(why)
  | Ok(_) =>
    switch await deploy() {
    | Error(why) => Error(why)
    | Ok(_) => (await remove())->Result.map(_ => ())
    }
  }
