/***
 * A behavior file run against an implementation, RFC p8e8k, through a `target`, what reaches it:
 * every case from nothing, each step in order, `within` retried after 100 ms doubling to at most 2 s
 * until it answers as expected or its time is past, every case run in CBOR and then in JSON. A
 * case needing what the target does not offer is skipped, naming why, never passed. The model's
 * interface, `docs/code.md`.
 */

/** The two forms a call is made in, CBOR the platform's own. */
type form = Cbor | Json

/** What a call or a send was answered: an output or an export's answer, or an error. */
type answered = Answered(JSON.t) | Failed({failure: string, reason: string, message: string})

/** What reaches an implementation, and what it offers a run beyond its calls. */
type target = {
  /** An operation of the interface called with its input, in a form, signed as a component if named. */
  call: (
    ~interface: string,
    ~operation: string,
    ~input: JSON.t,
    ~form: form,
    ~as_: option<string>,
  ) => promise<result<answered, string>>,
  /** What is deployed called at its address, by an export, for an instance by its key. */
  send: (
    ~to: string,
    ~export: string,
    ~key: option<string>,
    ~body: option<JSON.t>,
  ) => promise<result<answered, string>>,
  /** A case's `given` set up through the contracts above the implementation, or why it cannot be. */
  given: (~interface: string, JSON.t) => promise<result<unit, Filling.unfilled>>,
  /** The copies lost, by how many, or why the target cannot. */
  lose: int => promise<result<unit, Filling.unfilled>>,
  /** A bound by name. */
  bound: string => option<float>,
  /** A fixture's hash as built, where the target builds fixtures. */
  fixture: string => option<string>,
  /** How a `$signed` value is verified and read, by the run's trust. */
  signed: Matching.signed,
  /** Now, in milliseconds since the epoch. */
  now: unit => float,
  /** So many milliseconds passed, by a clock the target holds or by sleeping. */
  wait: int => promise<unit>,
}

/** How a case ended, in a form: passed, failed at a step with why, or skipped with why. */
type outcome =
  | Passed
  | Failed({step: int, why: string})
  | Skipped(string)

/** A case's outcome in each form it ran in. */
type result_ = {description: string, outcomes: array<(form, outcome)>}

/** Every case of the file, run against the target. */
let file: (Sample.file, target) => promise<array<result_>>
