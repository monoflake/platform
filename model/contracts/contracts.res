/**
 * Every contract together, and the product written from them, RFC fhg6w: `subset/`, the language
 * they are written in; `kinds/`, the interfaces the drivers give, each named in the plural; and
 * `records/`, the records' contents by product, each in the singular, so no two modules share a
 * name, ReScript's being one space across the model.
 */
open Subset

let types: array<declared> = Array.flat([
  Calls.types,
  Storage.types,
  Objects.types,
  Databases.types,
  Management.types,
  Deployments.types,
])
let contents: array<content> = Storage.contents
let interfaces: array<interface_> = [
  Objects.interface_,
  Databases.interface_,
  Management.interface_,
  Deployments.interface_,
]

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
    "reasons": Array(
      Calls.common->Array.map(r => JSON.Object(
        dict{"name": String(r.name), "failure": String((r.failure :> string))},
      )),
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
