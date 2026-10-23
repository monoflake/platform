/***
 * A call to a host's driver through its reach, as `code/tools/deploy` makes one over ssh, the
 * binding's token its bearer, RFCs vr5lw and 3d3nt.
 */

/** Why a call answered no output, its reason and message; `unreachable` where nothing answered. */
type refused = {reason: string, message: string}

/** Where the driver is and the token it takes. */
type host = {reach: Reach.t, address: string, port: int, token: string}

/** A call's envelope sent, its output read as its type. */
let call: (
  host,
  JSON.t,
  JSON.t => result<'output, Envelope.Malformed.t>,
) => promise<result<'output, refused>>
