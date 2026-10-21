/***
 * `Contracts` held to the samples of `tests/codec/`, read as they stand: a sample's JSON read as
 * its type gives exactly its CBOR, as codec writes it, and that CBOR read back gives exactly its
 * JSON; a refused sample's JSON is a `Malformed.t`. `codec.rs` beside it is the same in Rust.
 */
open Node
open Sample

let samples = "tests/codec"
let each = (kind, f) => each(samples, kind, f)

test("each sample's JSON is read as its type into exactly its CBOR", () =>
  each("samples", (message, item) => {
    let name = item->member("type")->string
    deepEqual(cborOf(name, item->member("json")), item->member("cbor")->string->hex, ~message)
  })
)

test(
  "each sample's CBOR, read as codec reads what it writes, is its type's exactly as its JSON",
  () =>
    each("samples", (message, item) => {
      let name = item->member("type")->string
      let value = switch Cbor.decodeDeterministic(item->member("cbor")->string->hex) {
      | Ok(value) => value
      | Error(_) => fail(`${message}: not deterministic CBOR`)
      }
      deepEqual(Contracts.cborToJson(name, value)->read(name), item->member("json"), ~message)
    }),
)

test("each refused sample's JSON is malformed", () =>
  each("refused", (message, item) => {
    deepEqual(item->member("reason")->string, "malformed", ~message)
    let refused = switch Contracts.jsonToCbor(item->member("type")->string, item->member("json")) {
    | Some(Error(_)) => true
    | Some(Ok(_)) | None => false
    }
    ok(refused, ~message)
  })
)
