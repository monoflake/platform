/***
 * The app's deployment, a bundle of modules fetched from the machine's own directory, and how far
 * it has come, RFC vr5lw and RFC n0o4l.
 */
module Contracts = Envelope.Contracts

/** The `file:` address of an artifact copied into the directory the driver fetches from. */
let address: (~directory: string, ~hash: Uint8Array.t) => string

/** The artifact's file name there, its hash in hex. */
let fileName: Uint8Array.t => string

/**
 * A deploy of the bundle for the app, its version the artifact's hash, into the container given,
 * an isolate with no secrets or networks, as hello's first deploy was.
 */
let deploy: (
  ~app: float,
  ~hash: Uint8Array.t,
  ~address: string,
  ~into: float,
) => Contracts.DeploymentDeploy.t

/** The app's deployment, as describe asks it. */
let of_: float => Contracts.DeploymentOf.t

/** The host the entry hands to the app's deployment, `<id in 8 hex>.b<binding>`. */
let host: (~app: float, ~binding: string) => string

/** How far a deployment of a version has come. */
type progress = Running | Waiting | Elsewhere | Failed(string)

/**
 * Running at the version, waiting while it is made, elsewhere while another version is described,
 * or failed with why, stopped among it.
 */
let progress: (Contracts.DeploymentDescribed.t, Uint8Array.t) => progress
