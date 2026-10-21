/***
 * What the tests read the samples and write their values with, JSON, hex and `Contracts` by a
 * type's name.
 */
open Node
module Cbor = Codec.Cbor

let fail = message => JsError.throwWithMessage(message)

let member = (json, name) =>
  switch json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name)) {
  | Some(value) => value
  | None => fail(`no ${name} in ${JSON.stringify(json)}`)
  }

let string = json =>
  switch json->JSON.Decode.string {
  | Some(text) => text
  | None => fail(`${JSON.stringify(json)}: no string`)
  }

let list = json =>
  switch json->JSON.Decode.array {
  | Some(items) => items
  | None => fail(`${JSON.stringify(json)}: no array`)
  }

/** The bytes a hex string spells. */
let hex = text =>
  Uint8Array.fromArray(
    Array.fromInitializer(~length=String.length(text) / 2, i =>
      switch text->String.slice(~start=2 * i, ~end=2 * i + 2)->Int.fromString(~radix=16) {
      | Some(byte) => byte
      | None => fail(`${text}: not hex`)
      }
    ),
  )

let parse = text => JSON.parseOrThrow(text)

/** Each item of each sample file's list `kind`, with the file it stands in. */
let each = (samples, kind, f) => {
  let files =
    readdirSync(fromRoot(samples))
    ->Array.filter(file => file->String.endsWith(".json"))
    ->Array.toSorted(String.compare)
  ok(files->Array.length > 0, ~message=`${samples}: no samples`)
  files->Array.forEach(file =>
    readFileSync(fromRoot(`${samples}/${file}`))
    ->parse
    ->member(kind)
    ->list
    ->Array.forEach(item => f(`${file}: ${JSON.stringify(item)}`, item))
  )
}

let where = (malformed: Malformed.t) =>
  `${malformed.at
    ->Array.map(step =>
      switch step {
      | Field(name) => name
      | Index(i) => Int.toString(i)
      | Key(key) => key
      }
    )
    ->Array.join("/")}: ${malformed.expected}`

let read = (result, name) =>
  switch result {
  | Some(Ok(value)) => value
  | Some(Error(malformed)) => fail(`${name}, at ${where(malformed)}`)
  | None => fail(`no type ${name}`)
  }

let encoded = value =>
  switch Cbor.encode(value) {
  | Ok(bytes) => bytes
  | Error(OutOfRange | RepeatedKey | TooDeep) => fail("unwritable")
  }

let decoded = bytes =>
  switch Cbor.decode(bytes) {
  | Ok(value) => value
  | Error(_) => fail("not CBOR")
  }

let cborOf = (name, json) => Contracts.jsonToCbor(name, json)->read(name)->encoded
let jsonOf = (name, bytes) => Contracts.cborToJson(name, decoded(bytes))->read(name)
