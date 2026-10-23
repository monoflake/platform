/***
 * The driver stopped and started again on a test machine, and what a call to it answers while it
 * is stopped read, RFC rmll5.
 */

/** The driver's unit. */
let unit: string

/** The shell stopping the driver, failing unless it is stopped. */
let stop: string

/** The shell starting the driver and waiting until it answers a call with no token, 403. */
let start: string

/** The shell printing the driver's state, `active` while it runs. */
let state: string

/** A shell run with its stderr beside its stdout and its exit status printed on a last line. */
let statused: string => string

/** The most a call to a stopped driver may take to be refused, ssh's round trip included. */
let quick: float

/**
 * Whether what `statused` printed of a call is a refusal at once, no connection made, taking so
 * many milliseconds, and how it was refused or why it is no clean refusal.
 */
let refused: (string, ~took: float) => result<string, string>
