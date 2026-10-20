/**
 * The wire contracts, in the subset Rust and ReScript both hold natively, RFC fhg6w: declared here
 * once, and written out by `mise run check --write` as `model/contracts.json`, the one thing a language
 * reads. What is structural is derived -- every record's shell, its `description`, a reference typed
 * by the kind it names -- and only what is a kind's own is declared.
 *
 * A record encodes as JSON with its fields' names, and as CBOR with their keys, deterministic. Key 0
 * of a record's content is its `description`, every kind's, v7v3w; key 0 of a union is its case.
 * An enumeration is written as its name in JSON and as its code in CBOR, 13ixj's levels among them.
 */
/**
 * A primitive: a 32-bit integer, signed or not; a 64-bit signed one, SQLite's, a decimal string in
 * JSON, since a JavaScript number holds it not, and an integer in CBOR; one exact in a JavaScript number, under 2^53, for a
 * time in milliseconds or a size in bytes, b8f35; a 64-bit float; bytes, base64url and unpadded in
 * JSON, RFC 4648's fifth section, and read in that text alone, fhg6w; and a content's hash, 32 bytes in CBOR and its 64 lowercase hex
 * digits in JSON, as b8f35 writes it wherever it is text. An id is never one of these: it is `Id`,
 * typed by the kind it names.
 */
type prim = [#bool | #string | #float64 | #int32 | #uint32 | #int64 | #uint53 | #bytes | #hash]

/** The half a record is kept in, its footing's, v7v3w. */
type half = [#platform | #organization]

type rec shape =
  | Prim(prim)
  /** An id of a record kind of the half the record holding it is kept in, stored as its integer, 8
   * hex digits shown, b8f35: within one footing, so its control checks it exists and guards it. */
  | Id(string)
  /** An id of a kind of the other half, which its control never checks nor guards, kept by another. */
  | Across(half, string)
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
  /** A set of names, each a bit, its code a power of two: in CBOR the integer of the bits set, in
   * JSON an array of the names set, as WIT's `flags` is written, vr5lw. */
  | Flags(array<choice>)

/**
 * Whose a record's keys are: the subset's own, from 1, key 0 reserved; CWT's, a claim registered by
 * its number or one of the platform's own below -65536, RFC 8392, b8f35; or another standard's, as
 * the RFC its type cites registers them, COSE's among them.
 */
type keys = [#subset | #cwt | #standard]

type declared = {name: string, def: def, from: string, keys?: keys}

/**
 * A signed record, b8f35: a `COSE_Sign1` by Ed25519, its protected header derived -- `alg` -19, `kid`
 * the first 16 bytes of the BLAKE3 of the signer's public key, `typ` `monoflake:{name}:{version}` --
 * its content a claim set of CWT's, or a record of the subset's. None is a record of a footing.
 */
type signed = {name: string, version: int, form: [#claims | #record], content: string}

/** A kind of record of `model/graph/records.res` with its content declared, and its version, wnqvu. */
type content = {
  half: half,
  kind: string,
  version: int,
  content: string,
  /** Each set of its fields unique among its kind's rows, which its footing keeps as a table's key,
   * since only a key keeps a value unique, v7v3w; a field absent counts as one value. */
  unique?: array<array<string>>,
}

/**
 * An operation's failure, RFC 49qyg's outcomes but `success`: what a caller acts on, whatever the
 * reason, which is the operation's own and only told.
 */
type failure = [#rejected | #unavailable | #unknown]

type reason = {name: string, failure: failure}

/** An operation: its input and its output, each a record declared, and the reasons it may fail for. */
type operation = {name: string, input: string, output: string, reasons: array<reason>}

/**
 * An interface, a kind's contract among them, vr5lw: each operation reached at `POST
 * /{interface}/{operation}`, its input the body and its output or an `error` the answer, in JSON or
 * CBOR as the request chooses. Its version is raised as a record's is, wnqvu.
 */
type interface_ = {
  name: string,
  version: int,
  operations: array<operation>,
  /** The bounds a sample may be written against, by name, each an integer. */
  bounds?: dict<int>,
  /** The bounds each driver declares of its own, by name, which a runner asks the driver for [D8]. */
  declared?: array<string>,
  from: string,
}

let field = (name, key, shape) => {name, key, shape}
let optional = (name, key, shape) => {name, key, shape, optional: true}
let op = (name, input, output, reasons) => {
  name,
  input,
  output,
  reasons: reasons->Array.map(((name, failure)) => {name, failure}),
}
let codes = names => names->Array.mapWithIndex((name, i) => {name, code: i + 1})

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
let rec refers = (s: shape): array<[#type_(string) | #id(string) | #across(half, string)]> =>
  switch s {
  | Prim(_) => []
  | Id(kind) => [#id(kind)]
  | Across(half, kind) => [#across(half, kind)]
  | Type(name) => [#type_(name)]
  | List(s) | Map(s) => refers(s)
  }

let fieldsOf = (d: def) =>
  switch d {
  | Record(fields) => fields
  | Union({cases}) => cases->Array.flatMap(c => c.fields)
  | Enum(_) | Flags(_) => []
  }

let rec shapeJson = (s: shape): JSON.t =>
  switch s {
  | Prim(p) => Object(dict{"prim": String((p :> string))})
  | Id(kind) => Object(dict{"id": String(kind)})
  | Across(half, kind) => Object(dict{"id": String(kind), "half": String((half :> string))})
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

let defJson = (d: def, ~content): JSON.t =>
  switch d {
  | Record(fields) =>
    let all = content ? Array.concat([description], fields) : fields
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
  | Flags(choices) =>
    Object(
      dict{
        "flags": Array(
          choices->Array.map(c => JSON.Object(
            dict{"name": String(c.name), "code": Number(Int.toFloat(c.code))},
          )),
        ),
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

let interfaceJson = (i: interface_): JSON.t => Object(
  dict{
    "version": Number(Int.toFloat(i.version)),
    "bounds": Object(
      i.bounds->Option.getOr(dict{})->Dict.mapValues(b => JSON.Number(Int.toFloat(b))),
    ),
    "declared": Array(i.declared->Option.getOr([])->Array.map(d => JSON.String(d))),
    "operations": Array(
      i.operations->Array.map(o => JSON.Object(
        dict{
          "name": String(o.name),
          "input": String(o.input),
          "output": String(o.output),
          "reasons": Array(
            o.reasons->Array.map(r => JSON.Object(
              dict{"name": String(r.name), "failure": String((r.failure :> string))},
            )),
          ),
        },
      )),
    ),
  },
)
