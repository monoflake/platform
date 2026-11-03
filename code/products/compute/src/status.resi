/***
 * compute's `status(id)`, the one operation taking an id, RFC 49qyg and
 * model/contracts/products/effects.res. The model's interface, `docs/code.md`.
 */

/** What status answers: the call as known, an id never recorded, or one past its retention. */
type answer =
  | Known({outcome: option<string>, committed: array<int>, expires: float, finished: bool})
  | NotFound
  | Forgotten

/**
 * `Forgotten` where `now` is past `issued` plus `retention`, whether or not a record is left;
 * else `NotFound` where none was recorded; else what was recorded, with the stores' steps where
 * they answered, none committed and not finished where they did not.
 */
let answered: (
  ~recorded: option<(float, option<string>)>,
  ~steps: option<(array<int>, bool)>,
  ~issued: float,
  ~now: float,
  ~retention: float,
) => answer

/**
 * The answer's JSON as the envelope writes it: `{"Ok": <call-status>}` with the id, or
 * `{"Error": {"failure": "rejected", "reason": "not_found" | "forgotten", "message": ...}}`, the
 * message the reason's own from the contracts' messages.
 */
let json: (~id: string, answer) => JSON.t
