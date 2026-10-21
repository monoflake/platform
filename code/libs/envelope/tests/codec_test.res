/***
 * `Contracts` held to the samples of `tests/codec/`, each JSON giving exactly its CBOR and back, as
 * `codec.rs` is in Rust.
 */
open Node
open Sample

let samples = "tests/codec"
let each = (kind, f) => each(samples, kind, f)

/** What a sample is read as, by its type's name or its interface's, and both ways of reading it. */
let registry = item =>
  switch item
  ->JSON.Decode.object
  ->Option.map(o => (o->Dict.get("type"), o->Dict.get("interface"))) {
  | Some((Some(name), None)) => (string(name), Contracts.jsonToCbor, Contracts.cborToJson)
  | Some((None, Some(name))) => (string(name), Contracts.callJsonToCbor, Contracts.callCborToJson)
  | Some((Some(_), Some(_)) | (None, None)) | None =>
    fail(`${JSON.stringify(item)}: neither a type nor an interface`)
  }

test("each sample's JSON is read as its type into exactly its CBOR", () =>
  each("samples", (message, item) => {
    let (name, toCbor, _) = registry(item)
    let cbor = toCbor(name, item->member("json"))->read(name)->encoded
    deepEqual(cbor, item->member("cbor")->string->hex, ~message)
  })
)

test(
  "each sample's CBOR, read as codec reads what it writes, is its type's exactly as its JSON",
  () =>
    each("samples", (message, item) => {
      let (name, _, toJson) = registry(item)
      let value = switch Cbor.decodeDeterministic(item->member("cbor")->string->hex) {
      | Ok(value) => value
      | Error(_) => fail(`${message}: not deterministic CBOR`)
      }
      deepEqual(toJson(name, value)->read(name), item->member("json"), ~message)
    }),
)

test("each refused sample's JSON is malformed", () =>
  each("refused", (message, item) => {
    deepEqual(item->member("reason")->string, "malformed", ~message)
    let (name, toCbor, _) = registry(item)
    let refused = switch toCbor(name, item->member("json")) {
    | Some(Error(_)) => true
    | Some(Ok(_)) | None => false
    }
    ok(refused, ~message)
  })
)
