/***
 * What an organization's own control is given through this one, RFC rxmd9, a request relayed to a
 * host it bound and an object kept on the first host bound here into the organization.
 */

/** A relayed request's address, its port and the path the host is handed, `/` at least. */
type relayed = {address: string, port: int, path: string}

/** `/relay/<address>/<port>/...`; none where the path is no relay's. */
let routed: string => option<relayed>

/** Whether a path is an object call, `/object/<operation>`. */
let objected: string => bool

/**
 * The request passed to a relayed binding of the caller's organization at one of the ports given,
 * its `Proxy-Authorization` dropped and every other header as it came.
 */
let passed: (
  State.t,
  Reach.t,
  ~caller: Access.caller,
  ~ports: array<int>,
  Web.request,
  relayed,
  ~search: string,
) => promise<Web.response>

/**
 * The object call passed to the organization's storage binding's driver by that binding's token,
 * a write it has no bucket for making one and sent once more.
 */
let stored: (
  State.t,
  Reach.t,
  ~caller: Access.caller,
  ~port: int,
  ~wait: unit => promise<unit>,
  Web.request,
  ~path: string,
) => promise<Web.response>
