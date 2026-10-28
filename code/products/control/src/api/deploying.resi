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

/** The kinds a release runs as, those it declares or its form's where it declares none, emgxf. */
let runsAs: (
  ~kinds: option<array<Contracts.DeploymentKind.t>>,
  ~form: Contracts.DeploymentForm.t,
) => array<Contracts.DeploymentKind.t>

/** The kinds a binding offers, function and container where its describe names none, emgxf. */
let offered: Contracts.ManagementDescribed.t => array<Contracts.ManagementKind.t>

/**
 * The first of a release's kinds, in its order, that the binding offers; never instance, which the
 * control deploys nowhere yet, emgxf.
 */
let chosen: (
  ~runs: array<Contracts.DeploymentKind.t>,
  ~offered: array<Contracts.ManagementKind.t>,
) => option<Contracts.DeploymentKind.t>

/**
 * A deploy of a release's bundle for the app, its version the artifact's hash, into the container
 * given or none.
 */
let deploy: (
  ~app: float,
  ~hash: Uint8Array.t,
  ~form: Contracts.DeploymentForm.t,
  ~address: string,
  ~secrets: dict<Uint8Array.t>,
  ~network: array<Contracts.DeploymentNetwork.t>,
  ~ingress: option<array<Contracts.AppIngress.t>>=?,
  ~into: float=?,
) => Contracts.DeploymentDeploy.t

/** The binding's list as its driver's management describes it. */
let describeList: Driver.host => promise<result<Contracts.ManagementDescribed.t, Driver.refused>>

/** The app deployed on the binding `described`, into its container made first where it offers one
 * and `declared` told it, 0 for none, before the deploy; `wait` paces the asking, emgxf. */
let deployed: (
  Driver.host,
  ~described: Contracts.ManagementDescribed.t,
  ~app: float,
  ~hash: Uint8Array.t,
  ~form: Contracts.DeploymentForm.t,
  ~address: string,
  ~secrets: dict<Uint8Array.t>,
  ~network: array<Contracts.DeploymentNetwork.t>,
  ~ingress: option<array<Contracts.AppIngress.t>>=?,
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
