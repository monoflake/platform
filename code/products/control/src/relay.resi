/***
 * What an organization's own control is given through this one, RFC rxmd9, a request relayed to a
 * host it bound and an object kept on the first host bound here into the organization.
 */

/** Which listener of a host a relayed request is for, its driver's or its entry's. */
type listener = Driver | Entry

/** A relayed request's binding, its listener and the path the host is handed, `/` at least. */
type relayed = {binding: float, listener: listener, path: string}

/** `/relay/<binding>/<driver|entry>/...`; none where the path is no relay's. */
let routed: string => option<relayed>

/** Whether a path is an object call, `/object/<operation>`. */
let objected: string => bool

/**
 * The request passed to the host of a relayed binding of the caller's organization, its
 * `Proxy-Authorization` dropped and every other header as it came.
 */
let passed: (
  State.t,
  Reach.t,
  ~caller: Access.caller,
  ~ports: (int, int),
  Web.request,
  relayed,
  ~search: string,
) => promise<Web.response>

/**
 * The object call passed to the driver of the organization's storage binding, its
 * `Authorization` that binding's token, and the driver's answer as it came.
 */
let stored: (
  State.t,
  Reach.t,
  ~caller: Access.caller,
  ~port: int,
  Web.request,
  ~path: string,
) => promise<Web.response>
