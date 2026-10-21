/***
 * An answer held to what a step expects, RFC p8e8k: only what the sample writes.
 */
type captures = dict<JSON.t>

type mismatch = {at: string, expected: string, answered: string}

type signed = (Uint8Array.t, string) => result<JSON.t, string>

/** A sample's placeholder: an object of one key, `$`-led, as `model/checks/written/cases.res` reads it. */
let placeholder = (json: JSON.t) =>
  switch json->JSON.Decode.object->Option.map(Dict.toArray) {
  | Some([(key, value)]) if key->String.startsWith("$") => Some((key, value))
  | Some(_) | None => None
  }

let isAbsent = json =>
  switch placeholder(json) {
  | Some(("$absent", _)) => true
  | Some(_) | None => false
  }

let into = (at, step) => at == "" ? step : `${at}/${step}`

let show = json => JSON.stringify(json)

/** Whether two values are one, a map's keys in any order. */
let rec same = (a: JSON.t, b: JSON.t) =>
  switch (a->JSON.Decode.object, b->JSON.Decode.object) {
  | (Some(x), Some(y)) =>
    let keys = x->Dict.keysToArray
    keys->Array.length == y->Dict.keysToArray->Array.length &&
      keys->Array.every(key =>
        switch (x->Dict.get(key), y->Dict.get(key)) {
        | (Some(u), Some(v)) => same(u, v)
        | (Some(_) | None, Some(_) | None) => false
        }
      )
  | (Some(_), None) | (None, Some(_)) => false
  | (None, None) =>
    switch (a->JSON.Decode.array, b->JSON.Decode.array) {
    | (Some(x), Some(y)) =>
      x->Array.length == y->Array.length &&
        x->Array.everyWithIndex((u, i) => y->Array.get(i)->Option.mapOr(false, v => same(u, v)))
    | (Some(_), None) | (None, Some(_)) => false
    | (None, None) => show(a) == show(b)
    }
  }

let rec matching = (expected, answered, ~signed, captures, at) => {
  let mismatch = (expected, answered) => Error({at, expected, answered})
  switch placeholder(expected) {
  | Some(("$any", _)) => Ok(captures)
  | Some(("$absent", _)) => mismatch("absent", show(answered))
  | Some(("$capture", name)) =>
    switch name->JSON.Decode.string {
    | Some(name) =>
      let captured = captures->Dict.copy
      captured->Dict.set(name, answered)
      Ok(captured)
    | None => mismatch(`a capture's name, not ${show(name)}`, show(answered))
    }
  | Some(("$use", name)) =>
    switch name->JSON.Decode.string->Option.flatMap(name => captures->Dict.get(name)) {
    | Some(value) if same(value, answered) => Ok(captures)
    | Some(value) => mismatch(show(value), show(answered))
    | None => mismatch(`${show(name)} as captured, yet captured by no step before`, show(answered))
    }
  | Some(("$signed", spec)) =>
    let record = spec->JSON.Decode.object->Option.flatMap(o => o->Dict.get("record"))
    let claims = spec->JSON.Decode.object->Option.flatMap(o => o->Dict.get("claims"))
    switch (
      record->Option.flatMap(JSON.Decode.string),
      claims,
      answered->JSON.Decode.string->Option.flatMap(Envelope.Base64url.decode),
    ) {
    | (Some(record), Some(claims), Some(bytes)) =>
      switch signed(bytes, record) {
      | Ok(content) => matching(claims, content, ~signed, captures, at)
      | Error(why) => mismatch(`a ${record} verified`, why)
      }
    | (Some(record), Some(_), None) => mismatch(`a ${record}, signed`, show(answered))
    | (Some(_) | None, Some(_) | None, Some(_) | None) =>
      mismatch(`a $signed naming its record and its claims, not ${show(spec)}`, show(answered))
    }
  | Some((key, _)) => mismatch(`${key}, no placeholder an answer is matched by`, show(answered))
  | None =>
    switch (expected->JSON.Decode.object, expected->JSON.Decode.array) {
    | (Some(fields), _) =>
      switch answered->JSON.Decode.object {
      | Some(given) =>
        fields
        ->Dict.toArray
        ->Array.reduce(Ok(captures), (sofar, (name, value)) =>
          switch sofar {
          | Error(_) => sofar
          | Ok(captures) =>
            switch (given->Dict.get(name), isAbsent(value)) {
            | (None, true) => Ok(captures)
            | (None, false) =>
              Error({at: into(at, name), expected: show(value), answered: "absent"})
            | (Some(field), _) => matching(value, field, ~signed, captures, into(at, name))
            }
          }
        )
      | None => mismatch(show(expected), show(answered))
      }
    | (None, Some(items)) =>
      switch answered->JSON.Decode.array {
      | Some(given) if given->Array.length == items->Array.length =>
        items->Array.reduceWithIndex(Ok(captures), (sofar, item, i) =>
          switch (sofar, given->Array.get(i)) {
          | (Error(_), _) => sofar
          | (Ok(captures), Some(field)) =>
            matching(item, field, ~signed, captures, into(at, Int.toString(i)))
          | (Ok(_), None) => sofar
          }
        )
      | Some(_) | None => mismatch(show(expected), show(answered))
      }
    | (None, None) =>
      same(expected, answered) ? Ok(captures) : mismatch(show(expected), show(answered))
    }
  }
}

let matches = (~expected, ~answered, ~signed, captures) =>
  matching(expected, answered, ~signed, captures, "")
