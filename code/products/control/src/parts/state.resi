/***
 * What the control keeps, its organizations, bindings, releases and deployments, kept in D1 here
 * and behind this record wherever it runs, RFC rxmd9.
 */

/** An organization and the secret its own control presents. */
type organization = {id: float, secret: Uint8Array.t}

/**
 * A binding, its secret, the tunnel made for its host and the address its host is reached at, each
 * absent until it is bound. A relayed one's host is bound to an organization's own control.
 */
type binding = {
  id: float,
  organization: float,
  secret: Uint8Array.t,
  tunnel: option<string>,
  address: option<string>,
  relayed: bool,
}

/** A release by its hash in hex, its form and its size in bytes. */
type release = {hash: string, form: Envelope.Contracts.DeploymentForm.t, size: float}

/** An app's deployment, the binding running it, the release and the container it runs in. */
type deployment = {app: float, binding: float, release: string, capacity: float}

type t = {
  /** The organization holding a label, opened if none does, the secret given kept where none is. */
  openOrganization: (string, ~secret: Uint8Array.t) => promise<organization>,
  hasOrganization: float => promise<bool>,
  organizationSecret: float => promise<option<Uint8Array.t>>,
  openBinding: (~organization: float, ~secret: Uint8Array.t, ~relayed: bool) => promise<float>,
  binding: float => promise<option<binding>>,
  /** The organization's first binding its host bound here, where its objects are kept. */
  storage: float => promise<option<binding>>,
  tunneled: (~binding: float, ~tunnel: string) => promise<unit>,
  /** The address its host is reached at, written once the host can be reached there. */
  addressed: (~binding: float, ~address: string) => promise<unit>,
  /** A release kept, a second put of one hash changing nothing. */
  putRelease: release => promise<unit>,
  release: string => promise<option<release>>,
  /** What was declared of an app's deployment, written before its host is called. */
  deploy: deployment => promise<unit>,
  deployment: float => promise<option<deployment>>,
}

/** The state kept in a D1 database, its tables `migrations/`'. */
let ofDatabase: Stores.database => t
