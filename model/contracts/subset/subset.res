/**
 * The wire contracts in the subset Rust and ReScript both hold, declared once and written as
 * `model/contracts.json` by `mise run check --write`, RFC fhg6w.
 */
/**
 * A primitive of the wire, integers, a float, bytes, a hash and a secret, fhg6w and b8f35. An id is
 * never one of these but `Id`.
 */
type prim = [
  | #bool
  | #string
  | #float64
  | #int32
  | #uint32
  | #int53
  | #uint53
  | #bytes
  | #hash
  | #secret
]

/** The half a record is kept in, its footing's, v7v3w. */
type half = [#platform | #organization]

type rec shape =
  | Prim(prim)
  /**
   * An id of a record kind of the record's own half, stored as its integer within one footing,
   * b8f35.
   */
  | Id(string)
  /**
   * An id of a kind of the other half, which its control never checks nor guards, kept by another.
   */
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
  /**
   * A set of names each a bit, the integer of the bits in CBOR and an array of names in JSON, as
   * WIT's `flags`, vr5lw.
   */
  | Flags(array<choice>)

/**
 * Whose a record's keys are, the subset's from 1, CWT's, b8f35, or another standard's as its RFC
 * registers them.
 */
type keys = [#subset | #cwt | #standard]

type declared = {name: string, def: def, from: string, keys?: keys}

/**
 * A signed record, a `COSE_Sign1` by Ed25519 whose header is derived, its content CWT claims or a
 * record, b8f35.
 */
type signed = {name: string, version: int, form: [#claims | #record], content: string}

/**
 * A kind of record of `model/graph/records.res` with its content declared, and its version, wnqvu.
 */
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
 * An operation's failure, RFC 49qyg's outcomes but `success`, which a caller acts on whatever the
 * reason.
 */
type failure = [#rejected | #unavailable | #unknown]

type reason = {name: string, failure: failure}

/**
 * Who may call an operation, each kind known by a proof of its own, RFC 6x8su; `anyone` declared
 * outright, never assumed.
 */
type caller = [
  | #anyone
  | #account
  | #organization
  | #operator
  | #component
  | #authority
  | #host
  | #capability
]

/**
 * An operation, its declared input and output records, the reasons it may fail for and who may call
 * it.
 */
type operation = {
  name: string,
  input: string,
  output: string,
  reasons: array<reason>,
  callers: array<caller>,
}

/**
 * An interface, reached at `POST /{interface}/{operation}` with a `call` and answered in JSON or
 * CBOR, vr5lw and ge55b.
 */
type interface_ = {
  name: string,
  version: int,
  operations: array<operation>,
  /** The bounds a sample may be written against, by name, each an integer. */
  bounds?: dict<int>,
  /**
   * The bounds each driver declares of its own, by name, which a runner asks the driver for [D8].
   */
  declared?: array<string>,
  from: string,
}

let field = (name, key, shape) => {name, key, shape}
let optional = (name, key, shape) => {name, key, shape, optional: true}
let op = (name, input, output, reasons, ~callers) => {
  name,
  input,
  output,
  reasons: reasons->Array.map(((name, failure)) => {name, failure}),
  callers,
}
let codes = names => names->Array.mapWithIndex((name, i) => {name, code: i + 1})

/** The shell every record's row is, its kind, id, generation, version and content, v7v3w. */
let shell = [
  field("kind", 1, Prim(#string)),
  field("id", 2, Prim(#uint32)),
  field("generation", 3, Prim(#uint53)),
  field("version", 4, Prim(#uint32)),
  optional("content", 5, Prim(#bytes)),
]

/**
 * A call, the interface, the operation, the input at key 3 and the capabilities, fhg6w. `callInput`
 * writes the input apart.
 */
let call = [
  field("interface", 1, Prim(#string)),
  field("operation", 2, Prim(#string)),
  optional("capabilities", 4, List(Prim(#bytes))),
]
let callInput = ("input", 3)
let callTyp = "monoflake:call:1"

/**
 * An answer, a union by `status` holding the output as `data` or an `error`, RFC ge55b.
 * `answerData` writes the output apart.
 */
let answerTag = "status"
let answerSuccess = ("success", 1)
let answerData = ("data", 1)
let answerError = ("error", 2)

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
          "callers": Array(o.callers->Array.map(c => JSON.String((c :> string)))),
        },
      )),
    ),
  },
)
