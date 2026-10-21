/***
 * `Calls.serve` bound to the Fetch API, which a Worker and workerd both give a handler: a `Request` read
 * into `Calls.request`, the answer written back as a `Response`. The model's interface,
 * `docs/code.md`.
 */

/** The runtime's `Request`. */
type jsRequest

/** The runtime's `Response`. */
type jsResponse

/** A Fetch handler serving the interfaces given. */
let handler: (array<Calls.route>, ~trust: Calls.trust) => jsRequest => promise<jsResponse>
