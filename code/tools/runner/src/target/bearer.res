/***
 * Each case in each form on a binding of its own, by the token its calls carry, so none sees what
 * another left, as a driver's own tests run them.
 */

/** The tokens a file holds, one a line, in the order the cases and their forms take them. */
let tokens = text => text->String.split("\n")->Array.map(String.trim)->Array.filter(t => t != "")

/**
 * A target calling, sending and holding a case through one target in CBOR and another in JSON, the
 * rest the first's.
 */
let split = (~cbor: Run.target, ~json: Run.target): Run.target => {
  ...cbor,
  call: (~interface, ~operation, ~input, ~form, ~as_) =>
    switch form {
    | Cbor => cbor.call(~interface, ~operation, ~input, ~form, ~as_)
    | Json => json.call(~interface, ~operation, ~input, ~form, ~as_)
    },
  send: (~to, ~export, ~key, ~body, ~form) =>
    switch form {
    | Cbor => cbor.send(~to, ~export, ~key, ~body, ~form)
    | Json => json.send(~to, ~export, ~key, ~body, ~form)
    },
  given: (~interface, ~form, given) =>
    switch form {
    | Cbor => cbor.given(~interface, ~form, given)
    | Json => json.given(~interface, ~form, given)
    },
}

/**
 * Every case of the file beside its result, each run alone on a target of a token for its CBOR
 * and another for its JSON, the tokens taken in turn by `next`.
 */
let file = async (
  file: Sample.file,
  ~at: (~token: string) => Run.target,
  ~next: unit => string,
) => {
  let rec go = async (k, results) =>
    switch file.cases->Array.get(k) {
    | None => results
    | Some(case) =>
      let cbor = at(~token=next())
      let json = at(~token=next())
      let ran = await Run.file({...file, cases: [case]}, split(~cbor, ~json))
      await go(k + 1, results->Array.concat(ran->Array.map(result => (case, result))))
    }
  await go(0, [])
}
