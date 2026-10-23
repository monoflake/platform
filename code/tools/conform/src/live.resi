/***
 * What the live driver answers on its own binding, asked on the machine with the token read there
 * and never sent off it, so the running process is held and not its binary alone, RFC n0o4l.
 */
module Contracts = Envelope.Contracts

/** What a request was answered, its HTTP status and its body. */
type answered = {status: int, body: string}

/** What the shells below print, the body and then the status on a line of its own. */
let readAnswered: string => result<answered, string>

/** The shell calling management's describe with the live binding's token. */
let described: string

/** The shell calling describe with no token. */
let untokened: string

/** The shell calling an interface no driver serves, with the live binding's token. */
let unknown: string

/** The shell calling deployments' describe of an app's deployment with the live binding's token. */
let deployment: (~app: int) => string

/** The shell printing the live binding's id, what stands before its token's dot. */
let binding: string

/** The shell asking the live entry for `/` by the host of an app's deployment on the binding. */
let hello: (~app: int, ~binding: int) => string

/** The shell printing the machine's tunnel address, none where it has none. */
let tunnel: string

/** What describe answered read as the contract's list, or why it is not one. */
let list: answered => result<Contracts.ManagementDescribed.t, string>

/** Whether a call with no token is denied, 403 and `denied`, or why not. */
let denied: answered => result<unit, string>

/** Whether an unknown interface is refused as malformed, naming it, or why not. */
let refused: answered => result<unit, string>

/** Whether the entry answered hello, 200 and a body saying so, or why not. */
let greeted: answered => result<unit, string>
