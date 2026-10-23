/***
 * hello asked by several clients at once, each back to back, and how every ask was answered,
 * RFC ehm48.
 */

/** How an ask was answered, 200, refused with no connection made, or failed some other way. */
type outcome = Answered | Refused(string) | Failed(string)

/** One ask, when it began and ended in milliseconds, and how it was answered. */
type asked = {began: float, ended: float, outcome: outcome}

/** How many clients ask each path at once. */
let clients: int

/**
 * The shell asking hello through the entry from `clients` loops on the machine, each asking again
 * as an answer comes, until the file `stop` exists or half an hour has passed, one line per ask.
 */
let shell: (~app: int, ~binding: int, ~stop: string) => string

/** A line the shell printed, read as its ask, none where it is no such line. */
let read: string => option<asked>

/** What curl's exit status and the status it printed make of an ask. */
let curled: (~exit: int, ~status: string) => outcome

/** What a fetch through the tunnel answered, a 200 saying hello or a failure. */
let fetched: (~status: int, ~body: string) => outcome

/** What a fetch that threw makes of an ask, by the code of its cause, if it has one. */
let thrown: (~code: option<string>, ~message: string) => outcome
