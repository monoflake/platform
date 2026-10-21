/**
 * The executor's interface, a code's export run on an input in its kind's sandbox, storing nothing,
 * RFC vuanj. Input and output cross as the CBOR of a WIT value.
 */
open Subset

let types: array<declared> = [
  // Where code runs, a V8 isolate or WebAssembly, which a `derive` always does, vuanj.
  {
    name: "sandbox",
    def: Enum({choices: [{name: "v8", code: 1}, {name: "webassembly", code: 2}], ordered: false}),
    from: "vuanj",
  },
  // A `derive` is given its fuel, its declaration's; an `effect` is given none.
  {
    name: "run",
    def: Record([
      field("code", 1, Prim(#hash)),
      field("kind", 2, Type("function-kind")),
      field("export", 3, Prim(#string)),
      field("input", 4, Prim(#bytes)),
      optional("fuel", 5, Prim(#uint53)),
    ]),
    from: "vuanj",
  },
  {
    name: "panic-cause",
    def: Enum({
      choices: [{name: "fuel", code: 1}, {name: "trap", code: 2}, {name: "memory", code: 3}],
      ordered: false,
    }),
    from: "vuanj",
  },
  // What a run came to, the output its export returned or the panic it ended in.
  {
    name: "run-outcome",
    def: Union({
      tag: "name",
      cases: [
        {name: "returned", code: 1, fields: [field("output", 1, Prim(#bytes))]},
        {
          name: "panicked",
          code: 2,
          fields: [field("cause", 1, Type("panic-cause")), field("message", 2, Prim(#string))],
        },
      ],
    }),
    from: "vuanj",
  },
  {name: "ran", def: Record([field("outcome", 1, Type("run-outcome"))]), from: "vuanj"},
]

/**
 * A code no host holds is not found, since code is deployed before any call reaches it; a sandbox
 * no host offers, or none with room for one more, waits for one.
 */
let interface_: interface_ = {
  name: "executor",
  version: 1,
  from: "vuanj",
  operations: [
    op(
      "run",
      "run",
      "ran",
      [("not_found", #rejected), ("no_export", #rejected), ("no_sandbox", #unavailable)],
    ),
  ],
}
