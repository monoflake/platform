module Web = ControlOrganization.Web
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

/** Declared domains and mounts carried to their deployments through the host entry. */
/** The app a path's scope names and the path the app is handed, its scope dropped. */
type routed = {app: float, path: string}

/** A mount `/v{n}/{scope}/...` read from the organization's scope rows, none where it has no row.
 * The app receives what follows its scope, or `/` where nothing follows. */
let mounted: (State.reads, ~organization: float, string) => promise<option<routed>>

/** The host read exactly before its immediate parent wildcard, each an indexed point read. */
let named: (State.reads, string) => promise<option<float>>

/** The host the entry hands to an app, its id and binding in hex. */
let host: (~app: float, ~binding: float) => string

/**
 * The request passed to the entry as it came, but for its URL, and its `Host` and
 * `X-Forwarded-Host` each the app's host.
 */
let passed: (
  State.reads,
  Reach.t,
  ~port: int,
  Web.request,
  routed,
  ~search: string,
) => promise<Web.response>

/** The scope the gateway reserves for its organization's storage, RFC vr5lw. */
let storageScope: string

/**
 * The configured storage's app and binding for a path in its reserved scope, from `{id}.b{binding}`
 * as the gateway is deployed with it, until a control deploys storage; none for any other path.
 */
let stored: (~configured: string, string) => option<(float, float)>

/** A request passed to an app on a binding, the path given whole, as `passed` does for a mount. */
let reached: (
  State.reads,
  Reach.t,
  ~port: int,
  Web.request,
  ~app: float,
  ~binding: float,
  ~path: string,
  ~search: string,
) => promise<Web.response>

/**
 * The configured compute's app and binding from `{id}.b{binding}` as the gateway is deployed with
 * it, until a control deploys compute; none for any other text, RFC vuanj.
 */
let computed: string => option<(float, float)>

/**
 * A routed call sent to compute in place of its app, as `reached` sends it but to compute's host,
 * the app's own `{app}.b{binding}` in `target`. The gateway cannot read a function's kind, so every
 * routed call goes this way while compute is configured; compute passes one that is not an
 * `effect` to its app untouched and unclassified, RFC 49qyg. 404 where the app is not deployed.
 */
let through: (
  State.reads,
  Reach.t,
  ~port: int,
  Web.request,
  routed,
  ~compute: (float, float),
  ~search: string,
) => promise<Web.response>

/** An answer made again with `X-Content-Type-Options: nosniff` and, but for a PDF, the sandbox. */
let guarded: Web.response => Web.response
