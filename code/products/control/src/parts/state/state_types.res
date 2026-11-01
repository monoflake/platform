/***
 * What every store of the state hands out, the records and the two views over them, RFC rxmd9.
 */
module DeploymentForm = Envelope.Contracts.DeploymentForm
module DeploymentKind = Envelope.Contracts.DeploymentKind

type binding = {
  id: float,
  organization: float,
  secret: Uint8Array.t,
  tunnel: option<string>,
  address: option<string>,
  origin: option<string>,
  relayed: bool,
  bound: option<float>,
}

type organization = {id: float, secret: Uint8Array.t}

exception DomainHeld(string)

type release = {
  ingress?: array<Envelope.Contracts.AppIngress.t>,
  hash: string,
  form: DeploymentForm.t,
  size: float,
  kinds: option<array<DeploymentKind.t>>,
}

type deployment = {
  ingress?: array<Envelope.Contracts.AppIngress.t>,
  app: float,
  binding: float,
  release: string,
  capacity: float,
  kind: option<DeploymentKind.t>,
}

let ran = (d: deployment) => d.kind->Option.isSome || d.capacity != 0.

/** The binding fields a gateway needs, with no secret or tunnel credential. */
type reached = {address: option<string>, origin: option<string>, bound: option<float>}

/** The gateway's state view offers only routing reads, RFC oomwh. */
type reads = {
  domain: string => promise<option<float>>,
  mount: (~organization: float, ~scope: string) => promise<option<float>>,
  binding: float => promise<option<reached>>,
  deployment: float => promise<option<deployment>>,
}

type t = {
  openOrganization: (string, ~secret: Uint8Array.t) => promise<organization>,
  hasOrganization: float => promise<bool>,
  organizationSecret: float => promise<option<Uint8Array.t>>,
  openBinding: (
    ~organization: float,
    ~secret: Uint8Array.t,
    ~relayed: bool,
    ~random: unit => float,
  ) => promise<float>,
  binding: float => promise<option<binding>>,
  storage: float => promise<option<binding>>,
  addressedAt: string => promise<option<binding>>,
  tunneled: (~binding: float, ~tunnel: string) => promise<unit>,
  addressed: (~binding: float, ~address: string=?) => promise<option<string>>,
  unaddressed: (~binding: float, ~address: string) => promise<unit>,
  routed: (~binding: float) => promise<unit>,
  originated: (~binding: float, ~origin: string) => promise<bool>,
  domain: string => promise<option<float>>,
  putRelease: release => promise<unit>,
  release: string => promise<option<release>>,
  drawApp: (~random: unit => float) => promise<float>,
  forgetApp: float => promise<bool>,
  hasApp: float => promise<bool>,
  retireApp: float => promise<unit>,
  deploy: deployment => promise<unit>,
  deployment: float => promise<option<deployment>>,
}
