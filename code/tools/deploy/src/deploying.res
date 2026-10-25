module Contracts = Envelope.Contracts

let fileName = hash => `${Envelope.Hex.encode(hash)}.tar`

let address = (~directory, ~hash) => `file://${directory}/${fileName(hash)}`

let deploy = (~app, ~hash, ~address, ~into): Contracts.DeploymentDeploy.t => {
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
