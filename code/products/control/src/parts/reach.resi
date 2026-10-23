/***
 * A host reached at a port of its private address, through the Worker's `vpc_networks` binding
 * here, or locally with one address put in place of every host's, RFC rxmd9.
 */
type t = {
  /** The origin a port of a host's address is reached at. */
  origin: (~address: string, ~port: int) => string,
  fetch: Web.fetch,
}

/** Through a binding that reaches every route the account's tunnels announce. */
let network: Web.fetcher => t

/** Through the global fetch, to the address given in place of each host's. */
let local: string => t
