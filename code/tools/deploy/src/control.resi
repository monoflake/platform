/***
 * A deploy through a control, RFC rxmd9, the release put, deployed onto a binding and described by
 * the operator, and the app asked through the control's gateway.
 */
module Contracts = Envelope.Contracts

/** The environment variable the operator's secret is read from, never an argument. */
let operatorVariable: string

/**
 * A target naming a control, `control:<address>`, its address, a path beneath an origin where the
 * control is an app of another, or none where it is ssh's.
 */
let origin: string => option<result<string, string>>

/** The gateway's address of an app, `<origin>/v1/<id in 8 hex>/`. */
let gateway: (~origin: string, ~app: float) => string

/** A control as the operator calls it, and the fetch it is called through. */
type t = {
  origin: string,
  operator: string,
  fetch: (string, Web.init) => promise<Web.response>,
}

/** The release put, its artifact the bundle's bytes, with the kinds it declares where it does. */
let put: (
  t,
  ~kinds: array<Contracts.DeploymentKind.t>=?,
  Uint8Array.t,
) => promise<result<Contracts.ReleaseHeld.t, Machine.refused>>

/**
 * The release deployed onto a binding with its secrets and network, as its driver answered, under
 * the app given, or a new one the control draws where none is, its id in the answer's `runs`.
 */
let deploy: (
  t,
  ~binding: float,
  ~app: option<float>,
  ~hash: Uint8Array.t,
  ~secrets: dict<Uint8Array.t>,
  ~network: array<Contracts.DeploymentNetwork.t>,
) => promise<result<Contracts.DeploymentDescribed.t, Machine.refused>>

/** The app forgotten, one whose id was drawn and that never ran, as the control answered. */
let forget: (t, ~app: float) => promise<result<Contracts.ReleaseOf.t, Machine.refused>>

/**
 * The app retired, one that ran, its deployment stopped and deleted by its driver and then removed,
 * as the control answered.
 */
let retire: (t, ~app: float) => promise<result<Contracts.ReleaseOf.t, Machine.refused>>

/** The app's deployment as its host's driver describes it, through the control. */
let describe: (t, ~app: float) => promise<result<Contracts.DeploymentDescribed.t, Machine.refused>>

/** The app asked for its root through the gateway, its status and first line where it answered. */
let asked: (t, ~app: float) => promise<result<string, string>>
