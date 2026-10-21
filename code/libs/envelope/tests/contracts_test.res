/***
 * `Contracts` past what its samples hold: a name no type has, a field a reader does not know, where
 * a value is malformed, an integer read by its value, and a set of names given out of its order.
 * `contracts.rs` beside it is the same in Rust.
 */
open Node
open Sample

test("a name no type has is none", () => {
  ok(Contracts.jsonToCbor("no-such-type", JSON.Null)->Option.isNone)
  ok(Contracts.cborToJson("no-such-type", Cbor.Null)->Option.isNone)
})

test("a field a reader does not know is passed over, in JSON and in CBOR", () => {
  deepEqual(
    cborOf("object-range", parse(`{"start": 7, "length": 2, "later": [1]}`)),
    hex("a201070202"),
  )
  // Key 9 and the text key "a" are no field of an object's range.
  deepEqual(jsonOf("object-range", hex("a40107020209f56161f6")), parse(`{"start": 7, "length": 2}`))
})

let malformed = (at, expected): option<result<Cbor.value, Malformed.t>> => Some(
  Error({at, expected}),
)

test("a value not as its type writes it is malformed where it stands", () => {
  let json = (name, text) => Contracts.jsonToCbor(name, parse(text))
  deepEqual(
    json("object-read", `{"name": "a", "range": {"start": -1, "length": 1}}`),
    malformed([Field("range"), Field("start")], "an integer of 0 to 2^53 - 1"),
  )
  deepEqual(json("object-range", `{"start": 1}`), malformed([Field("length")], "present"))
  deepEqual(
    json("object-read", `{"name": "a", "range": null}`),
    malformed([Field("range")], "an object"),
  )
  deepEqual(
    json("database-value", `{"kind": "decimal"}`),
    malformed([Field("kind")], "one of null, integer, real, text, bytes"),
  )
  deepEqual(
    json("file-expected", `{"name": "hash", "hash": "${"AB"->String.repeat(32)}"}`),
    malformed([Field("hash")], "64 lowercase hex digits"),
  )
  deepEqual(
    json("rights", `["read", 1]`),
    malformed([Index(1)], "one of read, create, replace, delete, alter, call"),
  )
  deepEqual(
    json("rights", `["call", "call"]`),
    malformed([Index(1)], "one of read, create, replace, delete, alter, call"),
  )
  deepEqual(json("rights", `{"read": true}`), malformed([], "an array"))
  deepEqual(
    json("app-bindings", `{"app": {"one": 1, "two": -2}}`),
    malformed([Field("app"), Key("two")], "an integer of 0 to 2^32 - 1"),
  )
  let cbor = (name, text) =>
    Contracts.cborToJson(name, decoded(hex(text)))->Option.map(r => r->Result.map(_ => Cbor.Null))
  deepEqual(cbor("database-value", "a10009"), malformed([Field("kind")], "one of 1, 2, 3, 4, 5"))
  deepEqual(cbor("database-value", "a200030101"), malformed([Field("value")], "a finite float"))
  deepEqual(cbor("rights", "1840"), malformed([], "an integer of the bits 1, 2, 4, 8, 16, 32"))
  deepEqual(cbor("file-expected", "a2000201410f"), malformed([Field("hash")], "32 bytes"))
})

test("a set of names is read in any order and written in its own", () => {
  deepEqual(cborOf("rights", parse(`["create", "read"]`)), hex("03"))
  deepEqual(jsonOf("rights", hex("03")), parse(`["read", "create"]`))
})

test("a float, a hash and empty bytes are written as their shapes ask", () => {
  deepEqual(
    cborOf("database-value", parse(`{"kind": "real", "value": 1.5}`)),
    hex("a2000301f93e00"),
  )
  let hash = "00"->String.repeat(31) ++ "ff"
  let bytes = hex(`a20002015820${hash}`)
  deepEqual(cborOf("file-expected", parse(`{"name": "hash", "hash": "${hash}"}`)), bytes)
  deepEqual(jsonOf("file-expected", bytes), parse(`{"name": "hash", "hash": "${hash}"}`))
  deepEqual(cborOf("database-value", parse(`{"kind": "bytes", "value": ""}`)), hex("a200050140"))
})

test("an integer is read by its value, any number that is exactly one within its bounds", () => {
  deepEqual(cborOf("object-range", parse(`{"start": 1e2, "length": 5.0}`)), hex("a20118640205"))
  deepEqual(
    Contracts.jsonToCbor("object-range", parse(`{"start": 1, "length": 5.5}`)),
    malformed([Field("length")], "an integer of 0 to 2^53 - 1"),
  )
})

test("a float is finite, a NaN or an infinity in CBOR malformed", () => {
  let cbor = text =>
    Contracts.cborToJson("database-value", decoded(hex(text)))->Option.map(r =>
      r->Result.map(_ => Cbor.Null)
    )
  ["a2000301f97e00", "a2000301f97c00", "a2000301f9fc00"]->Array.forEach(text =>
    deepEqual(cbor(text), malformed([Field("value")], "a finite float"), ~message=text)
  )
})
