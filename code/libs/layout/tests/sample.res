/***
 * The samples read as they stand from their paths, JSON with hex in either case and content made
 * from a seed.
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

/** A member holding an integer. */
let intAt = (json, names) => json->numberAt(names)->Float.toInt

/**
 * The content a sample gives, `{xof, length}` as BLAKE3's extended output of the text, or
 * `{zeros}`.
 */
let content = json =>
  switch (member(json, "xof"), member(json, "zeros")) {
  | (Some(xof), None) => Blake3.hashWith(Node.utf8(xof->string), {dkLen: json->intAt(["length"])})
  | (None, Some(zeros)) => Uint8Array.fromLength(zeros->number->Float.toInt)
  | (Some(_), Some(_)) | (None, None) =>
    JsError.throwWithMessage(`${JSON.stringify(json)}: no one content`)
  }

/** A parcel's header, `{master, seed}`. */
let header = (json): Parcel.header => {
  master: json->numberAt(["master"]),
  seed: json->hexAt(["seed"]),
}

/**
 * Sealed bytes changed as a case says, cut to its `truncate` or with its `set` bytes written over
 * them.
 */
let changed = (bytes, case) =>
  switch (member(case, "truncate"), member(case, "set")) {
  | (Some(length), None) => bytes->TypedArray.slice(~start=0, ~end=length->number->Float.toInt)
  | (None, Some(set)) =>
    let copy = bytes->TypedArray.copy
    copy->Web.setFrom(set->hexAt(["bytes"]), set->intAt(["at"]))
    copy
  | (None, None) => bytes
  | (Some(_), Some(_)) => JsError.throwWithMessage(`${JSON.stringify(case)}: two changes`)
  }

/** The refusal a case names, a name alone or `{name: n}` as the name and the number. */
let refused = case =>
  switch case->at(["refused"]) {
  | named if named->JSON.Decode.string->Option.isSome => (named->string, None)
  | named =>
    switch named->JSON.Decode.object->Option.map(Dict.toArray) {
    | Some([(name, value)]) => (name, Some(value->number->Float.toInt))
    | Some(_) | None => JsError.throwWithMessage(`${JSON.stringify(named)}: no one refusal`)
    }
  }

/** The BLAKE3, unkeyed, of bytes too large to keep in a sample. */
let hashed = Blake3.hash
