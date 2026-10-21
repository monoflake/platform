/***
 * A target over HTTP, RFC vr5lw and RFC ge55b: an operation called as `POST
 * {base}/{interface}/{operation}`, its body a `call` in the form asked, `Content-Type` and `Accept`
 * saying which; an answer read by its `status` alone, the HTTP status read only where the body is
 * no answer, `unknown` then. A send is `POST {address}/{export}`, an instance's `POST
 * {address}/{key}/{export}`, its body JSON. What it offers past calls is what its configuration
 * gives: a call signed as a component where a chain is given, bounds as written, and no `given`,
 * `lose` or fixture, each refused as not offered. The model's interface, `docs/code.md`.
 */

/** A chain the run made, RFC p8e8k: each component's certificate and its key, and the root's key. */
type chain

/** A fresh chain for a run: a root, an intermediate, an authority, an organization, each component's. */
let chain: (~components: array<string>, ~now: float) => chain

/** The root's public key, which the implementation is started trusting. */
let root: chain => Uint8Array.t

/** The target at a base URL, signing as a component by the chain given, its bounds as written. */
let target: (~base: string, ~chain: option<chain>, ~bounds: dict<float>) => Run.target
