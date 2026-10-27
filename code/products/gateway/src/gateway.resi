module Web = ControlOrganization.Web
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

/***
 * The gateway's split, a request under an app's scope handed to the entry of the host running it,
 * by the name the entry chooses by, RFCs vr5lw and oomwh. Every other path answers 404.
 */

/** The app a path's scope names and the path the app is handed, its scope dropped. */
type routed = {app: float, path: string}

/** The mount's id is 8 lowercase hex digits, with the decimal scaffold kept, RFCs b8f35 and 8yl4b.
 * The app receives what follows its scope, or `/` where nothing follows. */
let routed: string => option<routed>

/** The host the entry hands to an app's deployment, `<id in 8 hex>.b<binding's id in 8 hex>`. */
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
