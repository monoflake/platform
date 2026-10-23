/***
 * A deploy through a control, RFC rxmd9, the release put, deployed onto a binding and described by
 * the operator, and the app asked through the control's gateway.
 */
module Contracts = Envelope.Contracts

/** The environment variable the operator's secret is read from, never an argument. */
let operatorVariable: string

/** A target naming a control, `control:<origin>`, its origin, or none where it is ssh's. */
let origin: string => option<result<string, string>>

/** The gateway's address of an app, `<origin>/v1/app-<id>/`. */
let gateway: (~origin: string, ~app: float) => string

/** A control as the operator calls it, and the fetch it is called through. */
type t = {
  origin: string,
  operator: string,
  fetch: (string, Web.init) => promise<Web.response>,
}

/** The release put, its artifact the bundle's bytes. */
let put: (t, Uint8Array.t) => promise<result<Contracts.ReleaseHeld.t, Machine.refused>>

/** The release deployed as the app onto a binding, as the binding's driver answered. */
let deploy: (
  t,
  ~binding: float,
  ~app: float,
  ~hash: Uint8Array.t,
) => promise<result<Contracts.DeploymentDescribed.t, Machine.refused>>

/** The app's deployment as its host's driver describes it, through the control. */
let describe: (t, ~app: float) => promise<result<Contracts.DeploymentDescribed.t, Machine.refused>>

/** The app asked for its root through the gateway, its answer's body where it is 200. */
let asked: (t, ~app: float) => promise<result<string, string>>
