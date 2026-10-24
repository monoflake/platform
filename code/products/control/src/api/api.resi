/***
 * The control's API, `organizations`, `bindings`, `reaches` and `releases`, each operation
 * answering only the caller it is for, RFC rxmd9, and refusing every other as `denied`.
 */

/** The parts the API stands on, each behind its own record, and what it is configured with. */
type parts = {
  state: State.t,
  artifacts: Artifacts.t,
  reach: Reach.t,
  /** None where the control holds no credential to make tunnels, as when it runs locally. */
  tunnels: option<Tunnels.t>,
  driverPort: int,
  /** The control's origin as its hosts reach it, where a driver fetches an artifact from. */
  origin: string,
  /** What paces the asking while a host makes a container. */
  wait: unit => promise<unit>,
}

/** The bytes a release's artifact may hold, `releases`' bound in the model. */
let artifactBound: float

/** The private address a binding's host is reached at, `10.200.0.0/16` by its id. */
let addressOf: float => string

/** The tunnel's name for a binding's host. */
let tunnelName: float => string

/** The interfaces served to a caller. */
let routes: (parts, Access.caller) => array<Serve.Calls.route>
