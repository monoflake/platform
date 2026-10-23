/***
 * A behavior file run against an implementation through a `target`, every case in CBOR and then
 * JSON, RFC p8e8k. The model's interface, `docs/code.md`.
 */

/** The two forms a call is made in, CBOR the platform's own. */
type form = Cbor | Json

/** What a call or a send was answered, an output, an export's answer or an error. */
type answered = Answered(JSON.t) | Failed({failure: string, reason: string, message: string})

/**
 * A fixture as the target serves it, its form, the address its artifact is fetched from, the hash
 * written beside it and the architecture an image is built for.
 */
type fixture = {form: string, address: string, hash: string, architecture: option<string>}

/** What reaches an implementation, and what it offers a run beyond its calls. */
type target = {
  /** An operation called with its input in a form, signed as a component if named. */
  call: (
    ~interface: string,
    ~operation: string,
    ~input: JSON.t,
    ~form: form,
    ~as_: option<string>,
  ) => promise<result<answered, string>>,
  /**
   * What is deployed called at its address, by an export, for an instance by its key, in a case's
   * form.
   */
  send: (
    ~to: string,
    ~export: string,
    ~key: option<string>,
    ~body: option<JSON.t>,
    ~form: form,
  ) => promise<result<answered, string>>,
  /**
   * What a case is held before its first step in a form, its `given` or what its kind is held where
   * it gives none, set up through the contracts above the implementation, or why it cannot be.
   */
  given: (
    ~interface: string,
    ~form: form,
    option<JSON.t>,
  ) => promise<result<unit, Filling.unfilled>>,
  /** The copies lost, by how many, or why the target cannot. */
  lose: int => promise<result<unit, Filling.unfilled>>,
  /** A bound by name. */
  bound: string => option<float>,
  /** A fixture by its name as built and served, or why the target offers none of it. */
  fixture: string => result<fixture, string>,
  /** How a `$signed` value is verified and read, by the run's trust. */
  signed: Matching.signed,
  /** Now, in milliseconds since the epoch. */
  now: unit => float,
  /** So many milliseconds passed, by a clock the target holds or by sleeping. */
  wait: int => promise<unit>,
}

/** How a case ended in a form, passed, failed at a step with why, or skipped with why. */
type outcome =
  | Passed
  | Failed({step: int, why: string})
  | Skipped(string)

/** A case's outcome in each form it ran in. */
type result_ = {description: string, outcomes: array<(form, outcome)>}

/** Every case of the file, run against the target. */
let file: (Sample.file, target) => promise<array<result_>>
