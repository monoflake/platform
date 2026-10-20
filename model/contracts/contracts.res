/** Every product's contracts together, and the product written from them, RFC fhg6w. */
open Subset

let types: array<declared> = Array.flat([Calls.types, Storage.types, Objects.types, Database.types])
let contents: array<content> = Storage.contents
let interfaces: array<interface_> = [Objects.interface_, Database.interface_]

/** The product: what every language reads, and nothing of the model's code. */
let product = (~half: string => string, ~writes: string => array<string>): JSON.t => Object(
  dict{
    "version": Number(1.),
    "shell": fieldsJson(shell),
    "types": Object(
      Dict.fromArray(
        types->Array.map(t => (
          t.name,
          defJson(t.def, ~content=contents->Array.some(c => c.content == t.name)),
        )),
      ),
    ),
    "interfaces": Object(Dict.fromArray(interfaces->Array.map(i => (i.name, interfaceJson(i))))),
    "records": Array(
      contents->Array.map(c => JSON.Object(
        dict{
          "kind": String(c.kind),
          "half": String(half(c.kind)),
          "writes": Array(writes(c.kind)->Array.map(w => JSON.String(w))),
          "version": Number(Int.toFloat(c.version)),
          "content": String(c.content),
        },
      )),
    ),
  },
)
