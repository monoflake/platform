/***
 * A target over HTTP, `POST {base}/{interface}/{operation}` with a `call` in the form asked, RFC
 * vr5lw and RFC ge55b. The model's interface, `docs/code.md`.
 */

/** A chain the run made, RFC p8e8k, each component's certificate and key, and the root's key. */
type chain

/**
 * A fresh chain for a run, a root, an intermediate, an authority, an organization and each
 * component's.
 */
let chain: (~components: array<string>, ~now: float) => chain

/** The root's public key, which the implementation is started trusting. */
let root: chain => Uint8Array.t

/**
 * Every certificate above the components', which an implementation verifying to the root is started
 * holding. A call carries its own in `kcwt`.
 */
let certificates: chain => array<Uint8Array.t>

/** The target at a base URL, signing as a component by the chain given, its bounds as written. */
let target: (~base: string, ~chain: option<chain>, ~bounds: dict<float>) => Run.target
