/***
 * The compute product's Worker, a component in front of its organization's apps, RFCs 49qyg and
 * vuanj: the gateway sends it every call it routes, the app the call is for named in `target`. A
 * call to an `effect` is to be given an id, run once and its outcome told, its record kept in
 * `records`; until the contract's call id and records land, every call is passed to its app
 * untouched and unclassified, as a call that is not an `effect` always is. The model's interface,
 * `docs/code.md`.
 */

/** The runtime's `Request` and `Response`. */
type request
type response

/** The `database` contract's execute over its JSON, as the deploy fills a slot, RFC rt6gi. */
type records = {execute: JSON.t => promise<JSON.t>}

/**
 * What it is bound, each absent where it is not given: `ENTRY`, the origin its binding's apps are
 * reached at, the driver's; `records`, the database slot its metadata declares, the deploy's.
 */
type env = {
  @as("ENTRY") entry?: string,
  records?: records,
}

/** The app and binding `{app}.b{binding}` names, each 8 lowercase hex, none for any other text. */
let target: string => option<(float, float)>

/**
 * The request sent on to the app at `entry`, its method, body, path and search as they came, its
 * `Host` and `X-Forwarded-Host` the app's `{app}.b{binding}`, and `target` removed.
 */
let passed: (request, ~entry: string, ~app: float, ~binding: float) => promise<response>

/**
 * A call whose `target` names an app is passed to it and its answer returned as it came; a call
 * naming none answers 400, a Worker with no `ENTRY` 500, and an app that does not answer 503.
 */
let fetch: (request, env) => promise<response>

type worker = {fetch: (request, env) => promise<response>}

let default: worker
