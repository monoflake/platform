/**
 * Every contract together and the product written from them, RFC fhg6w. Each directory is named for
 * what it carries, so no two modules share a name.
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
  Organizations.types,
  Bindings.types,
  Releases.types,
  Blobs.types,
  Capabilities.types,
  Runs.types,
  Frames.types,
  Footings.types,
  Authorities.types,
  Directories.types,
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
  Organizations.interface_,
  Bindings.interface_,
  Releases.interface_,
  Blobs.interface_,
  Capabilities.interface_,
  Runs.interface_,
  Frames.interface_,
  Footings.interface_,
  Authorities.interface_,
  Authorities.notices,
  Directories.interface_,
]

/** The members of a declared enumeration, by its name, none where it is no enumeration. */
let members = set =>
  switch ownTypes->Array.find(t => t.name == set) {
  | Some({def: Enum({choices})}) => choices->Array.map(c => c.name)
  | Some({def: Record(_) | Union(_) | Flags(_)}) | None => []
  }

/** A capability as every language reads it, its default as `allowance-value` writes it. */
let capabilityJson = (c: Platform.capability): JSON.t => {
  let strings = names => JSON.Array(names->Array.map(n => JSON.String(n)))
  let some = names => JSON.Object(dict{"name": String("some"), "values": strings(names)})
  let amount = n => JSON.Object(dict{"name": String("amount"), "value": Number(Int.toFloat(n))})
  let (type_, of_, default) = switch c.type_ {
  | Flag({default}) => (
      "flag",
      None,
      JSON.Object(dict{"name": String("flag"), "value": Boolean(default)}),
    )
  | Amount({default}) => ("amount", None, amount(default))
  | OneOf({set, default}) => ("one", Some(members(set)), some(default))
  | SomeOf({set, default}) => ("some", Some(members(set)), some(default))
  | Amounts({members, default}) => ("amounts", Some(members), amount(default))
  }
  let o = dict{"name": JSON.String(c.name), "type": String(type_), "default": default}
  of_->Option.forEach(m => o->Dict.set("members", strings(m)))
  Object(o)
}

/** The product, what every language reads, and nothing of the model's code. */
let product = (~writes: (half, string) => array<string>): JSON.t => Object(
  dict{
    "version": Number(1.),
    "shell": fieldsJson(shell),
    "call": Object(
      dict{
        "fields": {
          let (name, key) = callInput
          let input = JSON.Object(
            dict{
              "name": JSON.String(name),
              "key": JSON.Number(Int.toFloat(key)),
              "shape": JSON.Object(dict{"input": JSON.String("operation")}),
            },
          )
          // By key, the interface and the operation, the input and then the capabilities.
          let before = call->Array.filter(f => f.key < key)->Array.map(fieldJson)
          let after = call->Array.filter(f => f.key > key)->Array.map(fieldJson)
          JSON.Array(Array.concatMany(before, [[input], after]))
        },
        "typ": String(callTyp),
      },
    ),
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
    "answer": {
      let ((success, successCode), (data, dataKey), (error, errorCode)) = (
        answerSuccess,
        answerData,
        answerError,
      )
      Object(
        dict{
          "tag": String(answerTag),
          "cases": Array([
            Object(
              dict{
                "name": String(success),
                "code": Number(Int.toFloat(successCode)),
                "fields": Array([
                  Object(
                    dict{
                      "name": String(data),
                      "key": Number(Int.toFloat(dataKey)),
                      "shape": Object(dict{"output": String("operation")}),
                    },
                  ),
                ]),
              },
            ),
            Object(
              dict{
                "name": String(error),
                "code": Number(Int.toFloat(errorCode)),
                "type": String("error"),
              },
            ),
          ]),
        },
      )
    },
    "reasons": Array(
      Calls.common->Array.map(r => JSON.Object(
        dict{"name": String(r.name), "failure": String((r.failure :> string))},
      )),
    ),
    "messages": Object(
      Calls.messages
      ->Dict.toArray
      ->Array.toSorted(((a, _), (b, _)) => String.compare(a, b))
      ->Array.map(((n, m)) => (n, JSON.String(m)))
      ->Dict.fromArray,
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
    "vocabulary": Array(Platform.vocabulary->Array.map(capabilityJson)),
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
