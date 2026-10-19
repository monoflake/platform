/**
 * The wire contracts, in the subset Rust and ReScript both hold natively, RFC fhg6w: declared here
 * once, and written out by `check.res --write` as `model/contracts.json`, the one thing a language
 * reads. What is structural is derived -- every record's shell, its `description`, a reference typed
 * by the kind it names -- and only what is a kind's own is declared.
 *
 * A record encodes as JSON with its fields' names, and as CBOR with their keys, deterministic. Key 0
 * of a record's content is its `description`, every kind's, v7v3w; key 0 of a union is its case.
 * An enumeration is written as its name in JSON and as its code in CBOR, 13ixj's levels among them.
 */
/**
 * A primitive: a 32-bit integer, signed or not; one exact in a JavaScript number, under 2^53, for a
 * time in milliseconds or a size in bytes, b8f35; a 64-bit float; bytes. An id is never one of
 * these: it is `Id`, typed by the kind it names.
 */
type prim = [#bool | #string | #float64 | #int32 | #uint32 | #uint53 | #bytes]

type rec shape =
  | Prim(prim)
  /** An id of a record kind, stored as its integer, 8 hex digits shown, b8f35. */
  | Id(string)
  /** A type declared below, by its name. */
  | Type(string)
  | List(shape)
  /** A map keyed by text. */
  | Map(shape)

type field = {name: string, key: int, shape: shape, optional?: bool}

type choice = {name: string, code: int}

type case = {name: string, code: int, fields: array<field>}

type def =
  | Record(array<field>)
  /** An enumeration; an ordered one compares by its codes, which start at 1, 13ixj. */
  | Enum({choices: array<choice>, ordered: bool})
  /** A union, its case named in the field `tag`, as ReScript's `@tag` lays it out. */
  | Union({tag: string, cases: array<case>})

type declared = {name: string, def: def, from: string}

/** A kind of record of `graph.res`'s `records` with its content declared, and its version, wnqvu. */
type content = {kind: string, version: int, content: string}

let field = (name, key, shape) => {name, key, shape}
let optional = (name, key, shape) => {name, key, shape, optional: true}
let codes = names => names->Array.mapWithIndex((name, i) => {name, code: i + 1})

let types: array<declared> = [
  {
    name: "bucket-type",
    def: Enum({choices: codes(["file", "object"]), ordered: false}),
    from: "13ixj",
  },
  {
    name: "availability",
    def: Enum({
      choices: codes([
        "opportunistic",
        "best_effort",
        "stable",
        "recoverable",
        "redundant",
        "multiregion",
      ]),
      ordered: true,
    }),
    from: "13ixj",
  },
  {
    name: "durability",
    def: Enum({
      choices: codes([
        "ephemeral",
        "persistent",
        "redundant",
        "replicated",
        "multizone",
        "multiregion",
      ]),
      ordered: true,
    }),
    from: "13ixj",
  },
  // Custody's codes are 0 and 1, compared as integers, though it is no ordered level, 13ixj.
  {
    name: "custody",
    def: Enum({choices: [{name: "false", code: 0}, {name: "true", code: 1}], ordered: false}),
    from: "13ixj",
  },
  {
    name: "placement",
    def: Record([
      field("availability", 1, Type("availability")),
      field("durability", 2, Type("durability")),
      field("custody", 3, Type("custody")),
    ]),
    from: "13ixj",
  },
  // How many copies at least lie in different ones of each domain, none more than `copies`.
  {
    name: "distinct",
    def: Record([
      optional("node", 1, Prim(#uint32)),
      optional("site", 2, Prim(#uint32)),
      optional("account", 3, Prim(#uint32)),
      optional("zone", 4, Prim(#uint32)),
      optional("region", 5, Prim(#uint32)),
    ]),
    from: "13ixj",
  },
  {
    name: "spread",
    def: Record([field("copies", 1, Prim(#uint32)), field("distinct", 2, Type("distinct"))]),
    from: "13ixj",
  },
  // A packed bucket is compressed and sealed unless either is set false; an opaque one is neither.
  {
    name: "bucket-kind",
    def: Union({
      tag: "name",
      cases: [
        {
          name: "packed",
          code: 1,
          fields: [optional("compress", 1, Prim(#bool)), optional("seal", 2, Prim(#bool))],
        },
        {name: "opaque", code: 2, fields: []},
      ],
    }),
    from: "13ixj",
  },
  {
    name: "access",
    def: Enum({choices: codes(["private", "public"]), ordered: false}),
    from: "13ixj",
  },
  // A bucket holds no name: it is its id, shown by its organization's tree, v7v3w. Its type is fixed
  // as it is made; its quota, in bytes, is none unless set; the apps it is bindable by are all of
  // them unless set.
  {
    name: "bucket",
    def: Record([
      field("type", 1, Type("bucket-type")),
      field("kind", 2, Type("bucket-kind")),
      field("placement", 3, Type("placement")),
      field("spread", 4, Type("spread")),
      optional("quota", 5, Prim(#uint53)),
      field("access", 6, Type("access")),
      optional("bindable", 7, List(Id("app"))),
    ]),
    from: "13ixj",
  },
]

let contents: array<content> = [{kind: "bucket", version: 1, content: "bucket"}]

/**
 * The shell every record's row is, derived, v7v3w: its kind, its id, the generation that wrote it,
 * its version, and its content, absent once the record is deleted.
 */
let shell = [
  field("kind", 1, Prim(#string)),
  field("id", 2, Prim(#uint32)),
  field("generation", 3, Prim(#uint53)),
  field("version", 4, Prim(#uint32)),
  optional("content", 5, Prim(#bytes)),
]

/** Every kind's content opens with its description, free text, empty unless written, v7v3w. */
let description = optional("description", 0, Prim(#string))

/** Every name a shape refers to, the declared types' and the record kinds' its ids name. */
let rec refers = (s: shape): array<[#type_(string) | #id(string)]> =>
  switch s {
  | Prim(_) => []
  | Id(kind) => [#id(kind)]
  | Type(name) => [#type_(name)]
  | List(s) | Map(s) => refers(s)
  }

let fieldsOf = (d: def) =>
  switch d {
  | Record(fields) => fields
  | Union({cases}) => cases->Array.flatMap(c => c.fields)
  | Enum(_) => []
  }

let rec shapeJson = (s: shape): JSON.t =>
  switch s {
  | Prim(p) => Object(dict{"prim": String((p :> string))})
  | Id(kind) => Object(dict{"id": String(kind)})
  | Type(name) => Object(dict{"type": String(name)})
  | List(s) => Object(dict{"list": shapeJson(s)})
  | Map(s) => Object(dict{"map": shapeJson(s)})
  }

let fieldJson = (f: field): JSON.t => {
  let o = dict{
    "name": JSON.String(f.name),
    "key": Number(Int.toFloat(f.key)),
    "shape": shapeJson(f.shape),
  }
  if f.optional->Option.getOr(false) {
    o->Dict.set("optional", Boolean(true))
  }
  Object(o)
}

let fieldsJson = fields => JSON.Array(fields->Array.map(fieldJson))

let defJson = (name, d: def): JSON.t =>
  switch d {
  | Record(fields) =>
    let all =
      contents->Array.some(c => c.content == name) ? Array.concat([description], fields) : fields
    Object(dict{"record": fieldsJson(all)})
  | Enum({choices, ordered}) =>
    Object(
      dict{
        "enum": Array(
          choices->Array.map(c => JSON.Object(
            dict{"name": String(c.name), "code": Number(Int.toFloat(c.code))},
          )),
        ),
        "ordered": Boolean(ordered),
      },
    )
  | Union({tag, cases}) =>
    Object(
      dict{
        "union": Object(
          dict{
            "tag": String(tag),
            "cases": Array(
              cases->Array.map(c => JSON.Object(
                dict{
                  "name": String(c.name),
                  "code": Number(Int.toFloat(c.code)),
                  "fields": fieldsJson(c.fields),
                },
              )),
            ),
          },
        ),
      },
    )
  }

/** The product: what every language reads, and nothing of the model's code. */
let product = (~half: string => string, ~writes: string => array<string>): JSON.t => Object(
  dict{
    "version": Number(1.),
    "shell": fieldsJson(shell),
    "types": Object(Dict.fromArray(types->Array.map(t => (t.name, defJson(t.name, t.def))))),
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
