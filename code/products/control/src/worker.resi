/*** The control answers calls, artifacts, relay and objects alone, RFC oomwh. */

/** Where every host is reached, the local address configured or the hosts' binding. */
let reachOf: Stores.env => option<Reach.t>

/** A request answered, its bindings, secrets and variables `wrangler.json`'s. */
type worker = {fetch: (Web.request, Stores.env) => promise<Web.response>}

let default: worker
