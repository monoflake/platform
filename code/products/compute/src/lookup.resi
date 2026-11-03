/***
 * A call whose outcome compute did not hear, looked up through the stores' status until an answer
 * or its deadline, RFC 49qyg and the author's H. The model's interface, `docs/code.md`.
 */

/** What the stores say of an id: the sequences committed and whether the one marked last did. */
type steps = {committed: array<int>, finished: bool}

/**
 * The step marked last committed, so a success; none committed and the id past its expiry, so
 * certainly not; or neither by the deadline, the last sequence known committed beside.
 */
type found = Finished | NotSeen | Open(option<int>)

/**
 * `steps` asked until `Finished`, or `NotSeen` once `now()` passes `expires` with none committed,
 * or the deadline passes, `deadline` milliseconds after the first ask; `wait` between asks. What
 * was found and how long it was looked up for, in milliseconds. A refused ask counts as none known.
 */
let looked: (
  ~steps: unit => promise<result<steps, string>>,
  ~expires: float,
  ~deadline: float,
  ~now: unit => float,
  ~wait: float => promise<unit>,
) => promise<(found, float)>
