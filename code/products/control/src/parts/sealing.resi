/***
 * A secret the control keeps, sealed by AES-256-GCM under the key in its `SEALING_KEY`, RFCs fhg6w
 * and b8f35, bound to the record and field it is kept in.
 */

/** The version a sealed secret begins with. */
let version: int

/** The key the control was given, or why it keeps no secret. */
type t

/** The key in a Worker's `SEALING_KEY`, 32 bytes in unpadded base64url, or why there is none. */
let ofKey: option<string> => t

/** A secret read, opened from its seal, or plain as kept before sealing and so to be sealed. */
type read = Opened(Uint8Array.t) | Plain(Uint8Array.t)

/** A secret sealed for its place, `kind:id:field`, as hex; a control with no key throws. */
let seal: (t, ~kind: string, ~id: float, ~field: string, Uint8Array.t) => promise<string>

/** A secret kept as hex read for its place; a seal that does not open throws, never read plain. */
let read: (t, ~kind: string, ~id: float, ~field: string, string) => promise<read>
