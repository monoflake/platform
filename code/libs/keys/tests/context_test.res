/***
 * `Context` held to `tests/keys/derived.json`'s contexts, every one in order.
 */
open Node
open Sample

let derived = "tests/keys/derived.json"

test("every context is listed, in order, as its text", () =>
  deepEqual(
    Context.all->Array.map(Context.text),
    read(derived)->at(["contexts"])->array->Array.map(string),
  )
)
