/***
 * The control this one stands on, which opens its hosts' reaches, the organization's own control
 * holding no Cloudflare credential, RFC rxmd9. The fetch is given, so a test answers it.
 */

/** A reach opened, its address and its tunnel's token where a tunnel was made. */
type reached = {address: string, tunnel: option<string>}

type t = {reach: unit => promise<result<reached, string>>}

/** The control stood on, by its origin, and the organization's token. */
let through: (~origin: string, ~token: string, Web.fetch) => t
