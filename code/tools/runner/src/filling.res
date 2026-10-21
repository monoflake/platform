/***
 * A step's input with its placeholders made, RFC p8e8k.
 */
type context = {
  description: string,
  step: int,
  captures: Matching.captures,
  now: float,
  bound: string => option<float>,
  fixture: string => option<string>,
}

type unfilled = Unoffered(string) | Unwritten(string)

exception Unfilled(unfilled)

let refuse = unfilled => throw(Unfilled(unfilled))

// The step's index counts from 0, as a sample's list does.
let bytes = (~description, ~step, ~path, length) =>
  length == 0
    ? Uint8Array.fromLength(0)
    : Noble.blake3(Web.utf8(`${description}/${Int.toString(step)}/${path}`), {dkLen: length})

/** A sample's placeholder, as `Matching` reads one. */
let placeholder = (json: JSON.t) =>
  switch json->JSON.Decode.object->Option.map(Dict.toArray) {
  | Some([(key, value)]) if key->String.startsWith("$") => Some((key, value))
  | Some(_) | None => None
  }

let field = (spec, name) => spec->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

/** A length as written: a number, or a bound and how many past it. */
let lengthOf = (spec, context, key) =>
  switch field(spec, "length") {
  | None => refuse(Unwritten(`${key} without a length`))
  | Some(length) =>
    switch (
      length->JSON.Decode.float,
      field(length, "bound")->Option.flatMap(JSON.Decode.string),
      field(length, "plus")->Option.flatMap(JSON.Decode.float),
    ) {
    | (Some(n), _, _) if Math.floor(n) == n && n >= 0. => Float.toInt(n)
    | (None, Some(bound), Some(plus)) =>
      switch context.bound(bound) {
      | Some(n) if n +. plus >= 0. => Float.toInt(n +. plus)
      | Some(_) =>
        refuse(Unwritten(`${key} short of nothing, ${bound} plus ${Float.toString(plus)}`))
      | None => refuse(Unoffered(`the bound ${bound}, which the run is given no value of`))
      }
    | (Some(_) | None, Some(_) | None, Some(_) | None) =>
      refuse(Unwritten(`${key}'s length, neither a number nor a bound and how many past it`))
    }
  }

let rec filled = (json, context, path) =>
  switch placeholder(json) {
  | Some(("$use", name)) =>
    switch name->JSON.Decode.string->Option.flatMap(name => context.captures->Dict.get(name)) {
    | Some(value) => value
    | None => refuse(Unwritten(`$use ${JSON.stringify(name)}, captured by no step before`))
    }
  | Some(("$time", spec)) =>
    switch field(spec, "ago")->Option.flatMap(JSON.Decode.float) {
    | Some(ago) => JSON.Number(Math.floor(context.now -. ago))
    | None => refuse(Unwritten("$time without how many milliseconds ago"))
    }
  | Some(("$bytes", spec)) =>
    let made = bytes(
      ~description=context.description,
      ~step=context.step,
      ~path,
      lengthOf(spec, context, "$bytes"),
    )
    JSON.String(Web.base64url(made))
  | Some(("$text", spec)) =>
    let start = field(spec, "start")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
    let length = lengthOf(spec, context, "$text")
    JSON.String(start->String.slice(~start=0, ~end=length)->String.padEnd(length, " "))
  | Some(("$fixture", name)) =>
    switch name->JSON.Decode.string {
    | Some(name) =>
      switch context.fixture(name) {
      | Some(hash) => JSON.String(hash)
      | None => refuse(Unoffered(`the fixture ${name}, which the run builds none of`))
      }
    | None => refuse(Unwritten("$fixture naming no fixture"))
    }
  | Some(("$frames", _)) =>
    refuse(Unoffered("$frames, the WAL frames a SQLite run inside the runner writes"))
  | Some((key, _)) => refuse(Unwritten(`${key}, no placeholder an input is made by`))
  | None =>
    switch (json->JSON.Decode.object, json->JSON.Decode.array) {
    | (Some(fields), _) =>
      JSON.Object(
        fields
        ->Dict.toArray
        ->Array.map(((name, value)) => (
          name,
          filled(value, context, path == "" ? name : `${path}/${name}`),
        ))
        ->Dict.fromArray,
      )
    | (None, Some(items)) =>
      JSON.Array(
        items->Array.mapWithIndex((item, i) =>
          filled(item, context, path == "" ? Int.toString(i) : `${path}/${Int.toString(i)}`)
        ),
      )
    | (None, None) => json
    }
  }

let fill = (json, context) =>
  try Ok(filled(json, context, "")) catch {
  | Unfilled(unfilled) => Error(unfilled)
  }
