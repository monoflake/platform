/**
 * Every contract together, and the product written from them, RFC fhg6w: `subset/`, the language
 * they are written in; `kinds/`, the interfaces the drivers give, each named in the plural; and
 * `records/`, the records' contents by product, each in the singular; and `products/`, the
 * interfaces the products give, each named for what it carries in the plural, so no two modules
 * share a name, ReScript's being one space across the model.
 */
open Subset

let ownTypes: array<declared> = Array.flat([
  Calls.types,
  Storage.types,
  Database.types,
  Compute.types,
  Control.types,
  Platform.types,
  Tables.types,
  Signed.types,
  Objects.types,
  Databases.types,
  Management.types,
  Deployments.types,
  Buckets.types,
  Generations.types,
])
let ownContents: array<content> = Array.flat([
  Storage.contents,
  Database.contents,
  Compute.contents,
  Control.contents,
  Platform.contents,
  Tables.contents,
])
/** Every type and content, with the platform half's own given beside, RFC 8lkuv. */
let types = Array.concat(ownTypes, Fill.part("types")->Option.getOr([]))
let contents = Array.concat(ownContents, Fill.part("contents")->Option.getOr([]))

let interfaces: array<interface_> = [
  Objects.interface_,
  Databases.interface_,
  Management.interface_,
  Deployments.interface_,
  Buckets.interface_,
  Generations.interface_,
]

/** The product: what every language reads, and nothing of the model's code. */
let product = (~writes: (half, string) => array<string>): JSON.t => Object(
  dict{
    "version": Number(1.),
    "shell": fieldsJson(shell),
    "types": Object(
      Dict.fromArray(
        ownTypes->Array.map(t => (
          t.name,
          {
            let j = defJson(t.def, ~content=ownContents->Array.some(c => c.content == t.name))
            switch (j->JSON.Decode.object, t.keys) {
            | (Some(d), Some(k)) if k != #subset =>
              d->Dict.set("keys", String((k :> string)))
              JSON.Object(d)
            | _ => j
            }
          },
        )),
      ),
    ),
    "reasons": Array(
      Calls.common->Array.map(r => JSON.Object(
        dict{"name": String(r.name), "failure": String((r.failure :> string))},
      )),
    ),
    "signed": Object(
      dict{
        "header": Object(
          dict{
            "alg": Number(-19.),
            "kid": String("the first 16 bytes of the BLAKE3 of the signer's public key"),
            "typ": String("monoflake:{name}:{version}"),
          },
        ),
        "records": Array(
          Signed.signed->Array.map(r => JSON.Object(
            dict{
              "name": String(r.name),
              "version": Number(Int.toFloat(r.version)),
              "form": String((r.form :> string)),
              "typ": String(`monoflake:${r.name}:${Int.toString(r.version)}`),
              "content": String(r.content),
            },
          )),
        ),
        "sections": Object(
          Dict.fromArray(Signed.sections->Array.map(((n, t)) => (n, JSON.String(t)))),
        ),
      },
    ),
    "calling": Array(
      Calls.calling->Array.map(r => JSON.Object(
        dict{"name": String(r.name), "failure": String((r.failure :> string))},
      )),
    ),
    "interfaces": Object(Dict.fromArray(interfaces->Array.map(i => (i.name, interfaceJson(i))))),
    "records": Array(
      ownContents->Array.map(c => JSON.Object(
        dict{
          "kind": String(c.kind),
          "half": String((c.half :> string)),
          "writes": Array(writes(c.half, c.kind)->Array.map(w => JSON.String(w))),
          "version": Number(Int.toFloat(c.version)),
          "content": String(c.content),
          "unique": Array(
            c.unique
            ->Option.getOr([])
            ->Array.map(u => JSON.Array(u->Array.map(f => JSON.String(f)))),
          ),
        },
      )),
    ),
  },
)
