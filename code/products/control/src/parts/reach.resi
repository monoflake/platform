/***
 * A host reached at a port of its private address, through the Worker's `vpc_networks` binding,
 * the relay of the control stood on, or locally at one address for every host, RFC rxmd9; or a
 * binding's driver at a public `https` origin, RFC 8j7b0.
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

/**
 * Through the relay of the control this one stands on, by its origin, the organization's token in
 * `Proxy-Authorization`.
 */
let relayed: (~origin: string, ~token: string, Web.fetch) => t

/**
 * At one `https` origin, whatever address and port a call names, through the fetch given, a
 * redirect answered as it is and never followed.
 */
let direct: (string, Web.fetch) => t
