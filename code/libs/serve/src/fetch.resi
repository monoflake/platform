/***
 * `Calls.serve` bound to the Fetch API a Worker and workerd both give. The model's interface,
 * `docs/code.md`.
 */

/** The runtime's `Request`. */
type jsRequest

/** The runtime's `Response`. */
type jsResponse

/** A Fetch handler serving the interfaces given. */
let handler: (array<Calls.route>, ~trust: Calls.trust) => jsRequest => promise<jsResponse>
