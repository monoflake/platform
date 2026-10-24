/***
 * A target's sends made as the host component makes a call, `Host.Handed.call`: the deployment
 * running at the address a step sends to described through the same target first, a stopped one
 * refused, and only then the request posted, RFCs b8f35 and p8e8k.
 */

/** The deployment a `deployments` answer names running at an address, by that address. */
let running: JSON.t => option<(string, JSON.t)>

/**
 * The target, each deployment it answers running remembered by its address, and its sends handed
 * through `Host.Handed.call` by that deployment, posted by `post`.
 */
let target: (Run.target, ~post: Host.Handed.post) => Run.target
