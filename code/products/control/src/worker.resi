/***
 * The control as a Worker, RFC rxmd9, a path under an app's scope passed to its host's entry, an
 * artifact fetched by its hash, and every other request a call of the API.
 */

/** Where every host is reached, the local address configured or the hosts' binding. */
let reachOf: Stores.env => option<Reach.t>

/** A request answered, its bindings, secrets and variables `wrangler.json`'s. */
type worker = {fetch: (Web.request, Stores.env) => promise<Web.response>}

let default: worker
