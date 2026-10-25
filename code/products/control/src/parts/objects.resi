/***
 * Objects kept through the control this one stands on, `/object/<operation>` by its organization's
 * token, RFC rxmd9, where no D1 or R2 is bound. The fetch is given, so a test answers it.
 */

type t = {
  write: (string, Uint8Array.t) => promise<result<unit, string>>,
  /** An object's bytes, none where no object has the name. */
  read: string => promise<result<option<Uint8Array.t>, string>>,
  /** Every name under a prefix, in byte order. */
  list: string => promise<result<array<string>, string>>,
  /** An object removed, none of that name being no fault. */
  delete: string => promise<result<unit, string>>,
}

/** The control stood on, by its origin, and the organization's token. */
let through: (~origin: string, ~token: string, Web.fetch) => t
