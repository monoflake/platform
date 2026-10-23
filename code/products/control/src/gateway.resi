/***
 * The gateway's split, a request under an app's scope handed to the entry of the host running it,
 * by the name the entry chooses by, RFCs vr5lw and rxmd9. Every other path is the control's API.
 */

/** The app a path's scope names and the path the app is handed, its scope dropped. */
type routed = {app: float, path: string}

/**
 * `/v{n}/app-{id}/...`, the app handed what follows, `/` at least, so it runs as it does on
 * Cloudflare, `docs/method.md`; none where the path is no app's.
 */
let routed: string => option<routed>

/** The host the entry hands to an app's deployment, `app-<id>.b<binding>`. */
let host: (~app: float, ~binding: float) => string

/**
 * The request passed to the entry as it came, but for its URL, and its `Host` and
 * `X-Forwarded-Host` each the app's host.
 */
let passed: (
  State.t,
  Reach.t,
  ~port: int,
  Web.request,
  routed,
  ~search: string,
) => promise<Web.response>
