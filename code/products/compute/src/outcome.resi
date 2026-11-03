/***
 * What compute tells of a call to an `effect` from what it heard, RFC 49qyg: success, `rejected`,
 * `unavailable`, or looked up before it may be `unknown`. The model's interface, `docs/code.md`.
 */

type outcome = Success | Rejected | Unavailable | Unknown

/** The outcome as the contract names it, `call-outcome`. */
let name: outcome => string

/**
 * What compute heard of a call: an answer, its status and the `failure` of an error answer in its
 * body where it is one; a request that never left; or one sent and never answered.
 */
type heard = Answered({status: int, failure: option<string>}) | Unsent | Lost

/** Told at once, or looked up first. */
type classified = Told(outcome) | Look

/**
 * An error answer's failure `rejected` or `unavailable` is told so, `unknown` is looked up; an
 * answer with no failure is a success below 500 and looked up from 500; `Unsent` is `unavailable`,
 * since nothing reached the function; `Lost` is looked up.
 */
let classified: heard => classified

/** The failure of an error answer's JSON body, `{"Error": {"failure": ...}}`, else none. */
let failureOf: JSON.t => option<string>
