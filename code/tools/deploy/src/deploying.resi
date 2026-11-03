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
 * an isolate with no secrets or networks, as hello's first deploy was, carrying `bindings` where
 * a build's slots are filled, RFC rt6gi.
 */
let deploy: (
  ~app: float,
  ~hash: Uint8Array.t,
  ~address: string,
  ~into: float,
  ~bindings: Contracts.AppBindings.t=?,
) => Contracts.DeploymentDeploy.t

/**
 * What fills a build's declared slots on a machine, each `database` slot the id given, or none
 * where the build declares no database slot, so a deploy of it carries no `bindings`.
 */
let bindings: (array<Contracts.ManifestSlot.t>, ~database: float) => option<Contracts.AppBindings.t>

/** The app's deployment, as describe asks it. */
let of_: float => Contracts.DeploymentOf.t

/** The host the entry hands to the app's deployment, `<id in 8 hex>.b<binding's id in 8 hex>`. */
let host: (~app: float, ~binding: float) => string

/** How far a deployment of a version has come. */
type progress = Running | Waiting | Elsewhere | Failed(string)

/**
 * Running at the version, waiting while it is made, elsewhere while another version is described,
 * or failed with why, stopped among it.
 */
let progress: (Contracts.DeploymentDescribed.t, Uint8Array.t) => progress

/** An archive held on the machine only while a deployment is made of it, kept if that fails. */
let held: (
  ~copy: unit => promise<result<'a, string>>,
  ~deploy: unit => promise<result<'b, string>>,
  ~remove: unit => promise<result<'c, string>>,
) => promise<result<unit, string>>
