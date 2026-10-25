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

/**
 * The app's deployment stopped and then deleted by its host's driver, gone once the delete is
 * answered; `not_found` from either is a deployment gone already.
 */
let retired: (Driver.host, ~app: float) => promise<result<unit, Driver.refused>>

/** The bytes the bucket made for an organization's objects holds, RFC rxmd9. */
let bucketSize: float

/**
 * The list with an `object` item added at the next generation where none is asked, every item
 * asked restated under a fresh credential, since describe gives none to keep.
 */
let bucketPlanned: (Contracts.ManagementDescribed.t, ~fresh: unit => Uint8Array.t) => planned

/** The binding's bucket, asked for and made where none is. */
let bucketed: (Driver.host, ~wait: unit => promise<unit>) => promise<result<unit, Driver.refused>>
