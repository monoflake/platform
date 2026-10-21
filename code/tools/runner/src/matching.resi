/***
 * An answer held to what a step expects, RFC p8e8k: what the sample names is checked and nothing
 * else. A field the sample leaves out is passed over, known to the contract or not; `$any` is a
 * field present with any value, `$absent` one absent, `$capture` records the value under a name,
 * `$use` holds it the same as captured, and `$signed` is verified to the run's root, then its claims
 * matched as any value is. The model's interface, `docs/code.md`.
 */

/** The values captured so far in a case, by name. */
type captures = dict<JSON.t>

/** Where an answer is not as expected: the path, by names and indices joined by `/`, and both. */
type mismatch = {at: string, expected: string, answered: string}

/**
 * How a `$signed` value is read: the bytes, by base64url as JSON writes them, verified by the run's
 * trust, its content then in JSON, as `capability*` verifies and `envelope*` writes it.
 */
type signed = (Uint8Array.t, string) => result<JSON.t, string>

/** The captures with what the answer added, or the first place it is not as expected. */
let matches: (
  ~expected: JSON.t,
  ~answered: JSON.t,
  ~signed: signed,
  captures,
) => result<captures, mismatch>
