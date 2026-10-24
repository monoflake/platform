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

/**
 * The target at a base URL, signing as a component by the chain given, its bounds as written, each
 * call carrying a binding's token where one is given, as a driver authenticates it, RFC 3d3nt.
 */
let target: (
  ~base: string,
  ~chain: option<chain>,
  ~bounds: dict<float>,
  ~token: string=?,
) => Run.target

/** A URL with no scheme read as plain HTTP, as a machine's bridge gives an address. */
let plainHttp: string => string

/** Where a send goes, by its address, an export and a key, an address with no scheme plain HTTP. */
let sendUrl: (~to: string, ~export: string, ~key: option<string>) => string

/** What a send was answered, by its HTTP status and its body. */
let sent: (int, Uint8Array.t) => Run.answered

/** A request posted from here over HTTP, as the host component posts a call, RFC b8f35. */
let handedPost: Host.Handed.post
