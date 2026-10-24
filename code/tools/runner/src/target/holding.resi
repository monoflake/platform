/***
 * What a case is held before its first step, an item of its kind's capacity applied through the
 * same driver's `management` on the case's own binding, as a control applies one, RFC p8e8k.
 */

/**
 * The capacity a case of an interface is held by what it gives, a given naming its own capacity
 * taken as named, none where neither it nor its kind names one.
 */
let capacity: (~interface: string, JSON.t) => option<JSON.t>

/** How long an item applied is waited on to be made, in milliseconds. */
let making: int

/**
 * A target's `given` by its `call`, each case held its `given` or else what `held` gives its
 * interface, the item waited on until it is made.
 */
let given: (
  ~call: (
    ~interface: string,
    ~operation: string,
    ~input: JSON.t,
    ~form: Run.form,
    ~as_: option<string>,
  ) => promise<result<Run.answered, string>>,
  ~now: unit => float,
  ~wait: int => promise<unit>,
  ~held: dict<JSON.t>,
) => (
  ~interface: string,
  ~form: Run.form,
  option<JSON.t>,
) => promise<result<unit, Filling.unfilled>>
