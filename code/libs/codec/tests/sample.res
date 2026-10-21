/***
 * The samples read as they stand from their paths, JSON through `JSON.Decode` with hex in either
 * case.
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

let items = path =>
  switch read(path)->at(["items"])->JSON.Decode.array {
  | Some(items) => items
  | None => JsError.throwWithMessage(`${path}: no items`)
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

let bytes = Uint8Array.fromArray

/** Bytes as the integers they hold. */
let ints = bytes =>
  Array.fromInitializer(~length=TypedArray.length(bytes), i =>
    bytes->TypedArray.get(i)->Option.getOr(0)
  )
