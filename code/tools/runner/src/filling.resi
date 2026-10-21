/***
 * A step's input with its placeholders made, RFC p8e8k, what the run does not offer refused. The
 * model's interface, `docs/code.md`.
 */

/**
 * What a filling reads, the case, the step, the captures, the time, the bounds and the fixtures.
 */
type context = {
  description: string,
  step: int,
  captures: Matching.captures,
  /** Now, in milliseconds since the epoch. */
  now: float,
  /** A bound by its name, the interface's or one its driver declares. */
  bound: string => option<float>,
  /** A fixture's hash as built, in hex, where the run builds fixtures. */
  fixture: string => option<string>,
}

/** Why an input could not be made, what the run does not offer or a placeholder not as written. */
type unfilled = Unoffered(string) | Unwritten(string)

/** The input with every placeholder made, or why it could not be. */
let fill: (JSON.t, context) => result<JSON.t, unfilled>

/** The bytes `$bytes` makes for a path of a step of a case, of a length. */
let bytes: (~description: string, ~step: int, ~path: string, int) => Uint8Array.t
