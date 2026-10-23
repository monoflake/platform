/***
 * A behavior file of `tests/` read as far as running it needs, taken as written since the model
 * checked it, RFC p8e8k. The model's interface, `docs/code.md`.
 */

/** What a step expects, an operation's output, an export's answer, or a failure and its reason. */
type expect =
  | Output(JSON.t)
  | Answer(JSON.t)
  | Failure({failure: string, reason: string})

/** A send, what is deployed called at its address by an export, and for an instance a key. */
type send = {to: JSON.t, export: string, key: option<string>, body: option<JSON.t>}

/** A step, in one of its four forms; `within` in milliseconds, `as_` a component's name. */
type step =
  | Call({
      operation: string,
      input: JSON.t,
      expect: expect,
      within: option<int>,
      as_: option<string>,
      fixture: option<string>,
    })
  | Send({send: send, expect: expect, within: option<int>})
  | Lose(int)
  | Wait(int)

/**
 * A case, its description, what it is given, the copies a database case is held on and its steps.
 */
type case = {description: string, given: option<JSON.t>, copies: option<int>, steps: array<step>}

/** A behavior file, its interface and its cases. */
type file = {interface: string, cases: array<case>}

/** The file its text writes, or where it is not a behavior file. */
let read: string => result<file, string>
