/***
 * An app deployed onto a bound host through its driver, its container asked for first where the
 * binding holds none, as `code/tools/deploy` does, RFCs vr5lw and rxmd9.
 */
module Contracts = Envelope.Contracts

/** What the app's container is asked for, as hello's first list asked. */
let capacity: Contracts.ManagementCapacity.t

/** What is sent to the binding for the app's container, or none when the list already holds one. */
type planned =
  | Held({into: float})
  | Apply({list: Contracts.ManagementApply.t, into: float})

/**
 * The list with a container added at the next generation if none is asked; one asking other items
 * is refused, as describe gives no credentials to keep them by.
 */
let planned: (Contracts.ManagementDescribed.t, ~credential: Uint8Array.t) => result<planned, string>

/** A deploy of a release's bundle for the app, its version the artifact's hash. */
let deploy: (
  ~app: float,
  ~hash: Uint8Array.t,
  ~form: Contracts.DeploymentForm.t,
  ~address: string,
  ~secrets: dict<Uint8Array.t>,
  ~network: array<Contracts.DeploymentNetwork.t>,
  ~into: float,
) => Contracts.DeploymentDeploy.t

/**
 * The app deployed at the release, its container made first, `declared` told the container before
 * the deploy is sent, and the driver's answer; `wait` paces the asking while the container is made.
 */
let deployed: (
  Driver.host,
  ~app: float,
  ~hash: Uint8Array.t,
  ~form: Contracts.DeploymentForm.t,
  ~address: string,
  ~secrets: dict<Uint8Array.t>,
  ~network: array<Contracts.DeploymentNetwork.t>,
  ~declared: float => promise<unit>,
  ~wait: unit => promise<unit>,
) => promise<result<Contracts.DeploymentDescribed.t, Driver.refused>>

/** The app's deployment as its host's driver describes it. */
let described: (
  Driver.host,
  ~app: float,
) => promise<result<Contracts.DeploymentDescribed.t, Driver.refused>>
