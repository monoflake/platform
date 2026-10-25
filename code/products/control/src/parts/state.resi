/***
 * What the control keeps, its organizations, bindings, releases and deployments, kept in D1 here
 * and behind this record wherever it runs, RFC rxmd9.
 */

/** An organization and the secret its own control presents. */
type organization = {id: float, secret: Uint8Array.t}

/**
 * A binding, its secret, its tunnel's id or token, its host's address or its driver's origin, RFC
 * 8j7b0, each absent until it is bound. A relayed one is an organization's own control's.
 */
type binding = {
  id: float,
  organization: float,
  secret: Uint8Array.t,
  tunnel: option<string>,
  address: option<string>,
  origin: option<string>,
  relayed: bool,
  /** The order it was bound in by a tunnel once its route was made; never for an origin binding. */
  bound: option<float>,
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
  openBinding: (
    ~organization: float,
    ~secret: Uint8Array.t,
    ~relayed: bool,
    ~random: unit => float,
  ) => promise<float>,
  binding: float => promise<option<binding>>,
  /**
   * The organization's first binding its host bound here by a tunnel, where its objects are kept,
   * never one reached by its origin, RFC 8j7b0.
   */
  storage: float => promise<option<binding>>,
  /** The binding reached at an address. */
  addressedAt: string => promise<option<binding>>,
  tunneled: (~binding: float, ~tunnel: string) => promise<unit>,
  /**
   * The address its host is reached at, `address` where given and it holds none, else the lowest in
   * `10.200.0.0/16` no binding holds, taken in one step; the one it holds, none where none is left.
   */
  addressed: (~binding: float, ~address: string=?) => promise<option<string>>,
  /** A binding's address given back, only where it still holds that one, as a failed make does. */
  unaddressed: (~binding: float, ~address: string) => promise<unit>,
  /** A binding's route made, its order taken after every one before, where it holds an address. */
  routed: (~binding: float) => promise<unit>,
  /**
   * The origin its driver is called at, written once proven and only where no bind fixed its reach
   * first, answering whether it was written, RFC 8j7b0.
   */
  originated: (~binding: float, ~origin: string) => promise<bool>,
  /** A release kept, a second put of one hash changing nothing. */
  putRelease: release => promise<unit>,
  release: string => promise<option<release>>,
  /**
   * An app's id drawn by `random`, kept by a conditional insert only where no app, binding or
   * organization holds it, and drawn again on a conflict, RFC b8f35.
   */
  drawApp: (~random: unit => float) => promise<float>,
  /** An app drawn and never run removed, no deployment or one of capacity 0, and whether it was. */
  forgetApp: float => promise<bool>,
  /** What was declared of an app's deployment, written before its host is called. */
  deploy: deployment => promise<unit>,
  deployment: float => promise<option<deployment>>,
}

/**
 * The state kept in a D1 database, its tables `migrations/`', each secret sealed under `sealing`; a
 * binding is inserted with an empty secret, then sealed for the id its insert gave.
 */
let ofDatabase: (Stores.database, ~sealing: Sealing.t) => t

/**
 * The state kept as objects, one JSON document a record under `state/`, where the control stands
 * on another and no D1 is bound, each secret sealed under `sealing`.
 */
let ofObjects: (Objects.t, ~sealing: Sealing.t) => t
