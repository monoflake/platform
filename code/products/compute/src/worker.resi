/***
 * The compute product's Worker, a component in front of its organization's apps, RFCs 49qyg and
 * vuanj: the gateway sends it every call it routes, the app the call is for named in `target`.
 * Each call is given an id, recorded in `records`, passed to its app once with the id in `Call`,
 * and its outcome told by Outcome, looked up by Lookup where not heard; `POST /compute/status`
 * answers by Status. The model's interface, `docs/code.md`.
 */

/** The runtime's `Request` and `Response`. */
type request
type response

/** The `database` contract's execute over its JSON, as the deploy fills a slot, RFC rt6gi. */
type records = {execute: JSON.t => promise<JSON.t>}

/** The apps' database item's status by a call's id, its `call-steps` or a throw with the reason. */
type database = {status: string => promise<JSON.t>}

/** A service binding, as `STORAGE` reaches the storage product. */
type service = {fetch: request => promise<response>}

/**
 * What it is bound, each absent where it is not given: `ENTRY`, the origin its binding's apps are
 * reached at, the driver's; `records`, the database slot its metadata declares, the deploy's;
 * `database` and `STORAGE`, the stores Lookup asks, the driver's; and in milliseconds an id's
 * life, the lookup's deadline and status's retention, which the deploy writes from
 * model/protocol/calls.json, never a literal here.
 */
type env = {
  @as("ENTRY") entry?: string,
  records?: records,
  database?: database,
  @as("STORAGE") storage?: service,
  @as("LIFE") life?: string,
  @as("DEADLINE") deadline?: string,
  @as("RETENTION") retention?: string,
}

/** The app and binding `{app}.b{binding}` names, each 8 lowercase hex, none for any other text. */
let target: string => option<(float, float)>

/**
 * The request sent on to the app at `entry`, its method, body, path and search as they came, its
 * `Host` and `X-Forwarded-Host` the app's `{app}.b{binding}`, and `target` removed.
 */
let passed: (request, ~entry: string, ~app: float, ~binding: float) => promise<response>

/**
 * What the stores say of call `id` of `app`, the database's and storage's committed sequences
 * unioned and sorted, finished where either says so. A store answering not_found has none
 * committed, one refused or unbound none known, and both so is an error.
 */
let steps: (
  ~database: option<database>,
  ~storage: option<service>,
  ~app: float,
  ~id: string,
) => promise<result<Lookup.steps, string>>

/**
 * A call whose `target` names an app is passed to it as above; its answer returned as it came with
 * its id in `Call`, a caller's own `Call` replaced, or where looked up and still open, an error
 * answer of failure `unknown` whose `call` holds the id, the time looked up and the last step; a
 * call naming none answers 400, a Worker missing `ENTRY` or a bound above 500.
 */
let fetch: (request, env) => promise<response>

type worker = {fetch: (request, env) => promise<response>}

let default: worker
