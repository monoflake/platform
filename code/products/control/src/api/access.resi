/***
 * Who calls the control at its thinnest, RFC rxmd9, the operator by the Worker's secret, a host by
 * its binding's token, RFC 3d3nt, an organization's own control by its own, and nobody else.
 */
type caller = Operator | Host(float) | Organization(float) | Nobody

/** The credential an `Authorization: Bearer` header carries. */
let bearer: option<string> => option<string>

/** A binding's token `<id>.<secret>` read, the secret 32 bytes. */
let token: string => option<(float, Uint8Array.t)>

/** A binding's token written. */
let tokenText: (float, Uint8Array.t) => string

/** An organization's token `o<id>.<secret>` read, the secret 32 bytes. */
let organizationToken: string => option<(float, Uint8Array.t)>

/** An organization's token written. */
let organizationText: (float, Uint8Array.t) => string

/** Whether two byte strings of one length are equal, in time that depends on their length alone. */
let equal: (Uint8Array.t, Uint8Array.t) => bool

/**
 * Who presented a credential, the operator's compared by its SHA-256 and a binding's or an
 * organization's secret by its bytes, each in constant time.
 */
let caller: (
  option<string>,
  ~operator: option<string>,
  ~secret: float => promise<option<Uint8Array.t>>,
  ~organizationSecret: float => promise<option<Uint8Array.t>>,
) => promise<caller>
