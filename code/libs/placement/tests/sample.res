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

/** A store, `{id, weight}`. */
let store = (json): Rendezvous.store => {
  id: json->numberAt(["id"]),
  weight: json->numberAt(["weight"])->Float.toInt,
}

/** The stores a member holds. */
let storesAt = (json, names) => json->at(names)->array->Array.map(store)

/** The refusal a case names, `"parcel"`, `{store}`, `{weight: {store, weight}}` or `{repeated}`. */
let refused = json => {
  let refused = json->at(["refused"])
  switch (
    refused->JSON.Decode.string,
    member(refused, "store"),
    member(refused, "weight"),
    member(refused, "repeated"),
  ) {
  | (Some("parcel"), None, None, None) => Rendezvous.Parcel
  | (None, Some(store), None, None) => Rendezvous.Store(store->number)
  | (None, None, Some(weight), None) =>
    Rendezvous.Weight({
      store: weight->numberAt(["store"]),
      weight: weight->numberAt(["weight"])->Float.toInt,
    })
  | (None, None, None, Some(repeated)) => Rendezvous.Repeated(repeated->number)
  | _ => JsError.throwWithMessage(`${JSON.stringify(refused)}: no one refusal`)
  }
}
