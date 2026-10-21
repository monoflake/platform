/***
 * Reading the samples as they stand, from their paths: JSON, read through `JSON.Decode`, its hex in
 * either case.
 */

/** The sample at `path`, from the repository's root. */
let read = path => Node.readFileSync(Node.fromRoot(path))->JSON.parseOrThrow

/** A member of a JSON object, if it is one and has it. */
let member = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

/** A member that must be there, by a path of names. */
let at = (json, names) =>
  names->Array.reduce(json, (json, name) =>
    switch member(json, name) {
    | Some(value) => value
    | None => JsError.throwWithMessage(`no ${name} in ${JSON.stringify(json)}`)
    }
  )

let string = json =>
  switch json->JSON.Decode.string {
  | Some(text) => text
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no string`)
  }

let number = json =>
  switch json->JSON.Decode.float {
  | Some(value) => value
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no number`)
  }

let array = json =>
  switch json->JSON.Decode.array {
  | Some(items) => items
  | None => JsError.throwWithMessage(`${JSON.stringify(json)}: no array`)
  }

/** The bytes a hex string spells. */
let hex = text =>
  Uint8Array.fromArray(
    Array.fromInitializer(~length=String.length(text) / 2, i =>
      switch text->String.slice(~start=2 * i, ~end=2 * i + 2)->Int.fromString(~radix=16) {
      | Some(byte) => byte
      | None => JsError.throwWithMessage(`${text}: not hex`)
      }
    ),
  )

/** A member holding hex, read as its bytes. */
let hexAt = (json, names) => json->at(names)->string->hex

/** A member holding a number. */
let numberAt = (json, names) => json->at(names)->number

/** The refusal a case names, `{length: {part, length}}` or `{range: {part}}`. */
let refused = json => {
  let refused = json->at(["refused"])
  switch (member(refused, "length"), member(refused, "range")) {
  | (Some(length), None) =>
    Derive.Length({
      part: length->at(["part"])->string,
      length: length->numberAt(["length"])->Float.toInt,
    })
  | (None, Some(range)) => Derive.Range({part: range->at(["part"])->string})
  | (Some(_), Some(_)) | (None, None) =>
    JsError.throwWithMessage(`${JSON.stringify(refused)}: no one refusal`)
  }
}
