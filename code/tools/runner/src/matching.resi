/***
 * An answer held to what a step expects, only what the sample names checked, RFC p8e8k. The model's
 * interface, `docs/code.md`.
 */

/** The values captured so far in a case, by name. */
type captures = dict<JSON.t>

/**
 * Where an answer is not as expected, the path by names and indices joined by `/`, and both values.
 */
type mismatch = {at: string, expected: string, answered: string}

/**
 * How a `$signed` value is read, its base64url bytes verified by the run's trust and its content
 * then in JSON.
 */
type signed = (Uint8Array.t, string) => result<JSON.t, string>

/** The captures with what the answer added, or the first place it is not as expected. */
let matches: (
  ~expected: JSON.t,
  ~answered: JSON.t,
  ~signed: signed,
  captures,
) => result<captures, mismatch>
