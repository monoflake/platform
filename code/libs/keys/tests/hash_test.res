/***
 * `Hash` held to `tests/keys/derived.json`'s hashes: keyed by a scope's salt, and unkeyed. Its
 * refusal is held with the rest, in `derive_test.res`.
 */
open Node
open Sample

let derived = "tests/keys/derived.json"

let cases = name => read(derived)->at(["hashed", name])->array

test("a content's id is BLAKE3 keyed by the scope's salt", () =>
  cases("keyed")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(
      Hash.keyed(~salt=item->hexAt(["salt"]), item->hexAt(["content"])),
      Ok(item->hexAt(["id"])),
      ~message,
    )
  })
)

test("a sealed parcel's id is BLAKE3 unkeyed", () =>
  cases("plain")->Array.forEach(item => {
    let message = JSON.stringify(item)
    deepEqual(Hash.plain(item->hexAt(["content"])), item->hexAt(["id"]), ~message)
  })
)
