type unread = {at: string, expected: string}

exception Unread(unread)

type prim = Bool | String | Float64 | Int32 | Uint32 | Int53 | Uint53 | Bytes | Hash | Secret

type rec shape =
  | Prim(prim)
  /** An id of either half, its kind's name read and no more, since on the wire it is an integer. */
  | Id
  | Type(string)
  | List(shape)
  | Map(shape)

type field = {name: string, key: int, shape: shape, optional: bool}
type choice = {name: string, code: int}
type case = {name: string, code: int, fields: array<field>}

type def =
  | Record(array<field>)
  | Enum(array<choice>)
  | Union({tag: string, cases: array<case>})
  | Flags(array<choice>)

type reason = {name: string, failure: string}
type operation = {name: string, input: string, output: string, reasons: array<reason>}
type interface_ = {name: string, version: int, operations: array<operation>}

/** A call's field: a shape of the subset's, or the input of the operation another field names. */
type callShape = Shape(shape) | Input(string)
type callField = {name: string, key: int, shape: callShape, optional: bool}

type contracts = {
  shell: array<field>,
  call: array<callField>,
  types: array<(string, def)>,
  reasons: array<reason>,
  calling: array<reason>,
  interfaces: array<interface_>,
}

let fail = (at, expected) => throw(Unread({at: at->Array.join("/"), expected}))

let caught = make =>
  try Ok(make()) catch {
  | Unread(unread) => Error(unread)
  }

// Reading `model/contracts.json`, each value by its path from the top.

let object = (json, at) =>
  switch json->JSON.Decode.object {
  | Some(o) => o
  | None => fail(at, "an object")
  }

let member = (o, at, name) =>
  switch o->Dict.get(name) {
  | Some(value) => value
  | None => fail([...at, name], "present")
  }

let text = (json, at) =>
  switch json->JSON.Decode.string {
  | Some(text) => text
  | None => fail(at, "a string")
  }

let integer = (json, at) =>
  switch json->JSON.Decode.float {
  | Some(n) if Float.isFinite(n) && Math.floor(n) == n && Math.abs(n) <= 2147483647. =>
    Float.toInt(n)
  | Some(_) | None => fail(at, "an integer of 32 bits")
  }

let items = (json, at, read) =>
  switch json->JSON.Decode.array {
  | Some(items) => items->Array.mapWithIndex((item, i) => read(item, [...at, Int.toString(i)]))
  | None => fail(at, "an array")
  }

let entries = (json, at, read) =>
  object(json, at)
  ->Dict.toArray
  ->Array.map(((name, value)) => (name, read(value, [...at, name])))

/** The one of `names` an object holds, its value beside it. */
let oneOf = (o, at, names) =>
  switch names->Array.filter(name => o->Dict.get(name)->Option.isSome) {
  | [name] => (name, member(o, at, name))
  | _ => fail(at, `one of ${names->Array.join(", ")}`)
  }

let prim = (json, at) =>
  switch text(json, at) {
  | "bool" => Bool
  | "string" => String
  | "float64" => Float64
  | "int32" => Int32
  | "uint32" => Uint32
  | "int53" => Int53
  | "uint53" => Uint53
  | "bytes" => Bytes
  | "hash" => Hash
  | "secret" => Secret
  | _ => fail(at, "a primitive of the subset")
  }

let rec shape = (json, at) => {
  let o = object(json, at)
  switch oneOf(o, at, ["prim", "id", "type", "list", "map"]) {
  | ("prim", p) => Prim(prim(p, [...at, "prim"]))
  | ("id", kind) =>
    let _: string = text(kind, [...at, "id"])
    Id
  | ("type", name) => Type(text(name, [...at, "type"]))
  | ("list", s) => List(shape(s, [...at, "list"]))
  | (_, s) => Map(shape(s, [...at, "map"]))
  }
}

let optional = (o, at) =>
  switch o->Dict.get("optional") {
  | Some(optional) =>
    switch optional->JSON.Decode.bool {
    | Some(optional) => optional
    | None => fail([...at, "optional"], "a boolean")
    }
  | None => false
  }

let field = (json, at): field => {
  let o = object(json, at)
  {
    name: text(member(o, at, "name"), [...at, "name"]),
    key: integer(member(o, at, "key"), [...at, "key"]),
    shape: shape(member(o, at, "shape"), [...at, "shape"]),
    optional: optional(o, at),
  }
}

let callField = (json, at): callField => {
  let o = object(json, at)
  let at_ = [...at, "shape"]
  let s = member(o, at, "shape")
  {
    name: text(member(o, at, "name"), [...at, "name"]),
    key: integer(member(o, at, "key"), [...at, "key"]),
    shape: switch object(s, at_)->Dict.get("input") {
    | Some(operation) => Input(text(operation, [...at_, "input"]))
    | None => Shape(shape(s, at_))
    },
    optional: optional(o, at),
  }
}

let fields = (json, at) => items(json, at, field)

let choice = (json, at): choice => {
  let o = object(json, at)
  {
    name: text(member(o, at, "name"), [...at, "name"]),
    code: integer(member(o, at, "code"), [...at, "code"]),
  }
}

let case = (json, at): case => {
  let o = object(json, at)
  {
    name: text(member(o, at, "name"), [...at, "name"]),
    code: integer(member(o, at, "code"), [...at, "code"]),
    fields: fields(member(o, at, "fields"), [...at, "fields"]),
  }
}

let def = (json, at) => {
  let o = object(json, at)
  switch oneOf(o, at, ["record", "enum", "union", "flags"]) {
  | ("record", f) => Record(fields(f, [...at, "record"]))
  | ("enum", c) => Enum(items(c, [...at, "enum"], choice))
  | ("union", u) =>
    let at = [...at, "union"]
    let u = object(u, at)
    Union({
      tag: text(member(u, at, "tag"), [...at, "tag"]),
      cases: items(member(u, at, "cases"), [...at, "cases"], case),
    })
  | (_, c) => Flags(items(c, [...at, "flags"], choice))
  }
}

let reason = (json, at): reason => {
  let o = object(json, at)
  {
    name: text(member(o, at, "name"), [...at, "name"]),
    failure: text(member(o, at, "failure"), [...at, "failure"]),
  }
}

let operation = (json, at) => {
  let o = object(json, at)
  {
    name: text(member(o, at, "name"), [...at, "name"]),
    input: text(member(o, at, "input"), [...at, "input"]),
    output: text(member(o, at, "output"), [...at, "output"]),
    reasons: items(member(o, at, "reasons"), [...at, "reasons"], reason),
  }
}

let interface_ = (name, json, at) => {
  let o = object(json, at)
  {
    name,
    version: integer(member(o, at, "version"), [...at, "version"]),
    operations: items(member(o, at, "operations"), [...at, "operations"], operation),
  }
}

let read = text =>
  caught(() => {
    let json = try JSON.parseOrThrow(text) catch {
    | JsExn(_) => fail([], "JSON")
    }
    let o = object(json, [])
    {
      shell: fields(member(o, [], "shell"), ["shell"]),
      // A call's `typ` is its Sign1's, made by whoever signs it, outside the envelope.
      call: items(
        member(object(member(o, [], "call"), ["call"]), ["call"], "fields"),
        ["call", "fields"],
        callField,
      ),
      types: entries(member(o, [], "types"), ["types"], def),
      reasons: items(member(o, [], "reasons"), ["reasons"], reason),
      calling: items(member(o, [], "calling"), ["calling"], reason),
      interfaces: entries(member(o, [], "interfaces"), ["interfaces"], (json, at) =>
        interface_(at->Array.at(-1)->Option.getOr(""), json, at)
      )->Array.map(((_, i)) => i),
    }
  })

// Names, as ReScript writes them.

/** The words ReScript's parser refuses as a field's or a value's name. */
let keywords = [
  "and",
  "as",
  "assert",
  "await",
  "constraint",
  "else",
  "exception",
  "external",
  "false",
  "for",
  "if",
  "in",
  "include",
  "let",
  "module",
  "mutable",
  "of",
  "open",
  "private",
  "rec",
  "switch",
  "true",
  "try",
  "type",
  "when",
  "while",
]

/** The modules the written source names beside its own, which no type's module may hide. */
let reserved = ["Wire", "Malformed", "Codec", "JSON", "Uint8Array", "Shell", "Interface"]

let words = name => name->String.replaceAll("-", "_")->String.split("_")
let capital = word => word->String.charAt(0)->String.toUpperCase ++ word->String.slice(~start=1)

let upperName = /^[A-Z][A-Za-z0-9]*$/
let lowerName = /^[a-z][A-Za-z0-9]*$/
let fieldName = /^[a-z][A-Za-z0-9_]*$/

let upper = (name, at) => {
  let upper = words(name)->Array.map(capital)->Array.join("")
  upperName->RegExp.test(upper) ? upper : fail(at, "a name of letters and digits")
}

let lower = (name, at) => {
  let lower = switch words(name) {
  | [] => ""
  | words => words->Array.mapWithIndex((word, i) => i == 0 ? word : capital(word))->Array.join("")
  }
  if !(lowerName->RegExp.test(lower)) {
    fail(at, "a name of letters and digits, opening with a lowercase one")
  }
  keywords->Array.includes(lower) ? `${lower}_` : lower
}

/** A field's name in ReScript, a keyword's followed by an underscore. */
let label = (name, at) => {
  if !(fieldName->RegExp.test(name)) {
    fail(at, "a name of lowercase letters, digits and underscores")
  }
  keywords->Array.includes(name) ? `${name}_` : name
}

let quote = text => JSON.stringify(JSON.String(text))

/** Each of `names` once, or where the second stands. */
let distinct = (names, at, expected) =>
  names->Array.forEachWithIndex((name, i) =>
    if names->Array.slice(~start=0, ~end=i)->Array.includes(name) {
      fail(at(i), expected)
    }
  )

// Writing the source.

type side = ToJson | FromJson | ToCbor | FromCbor

let sideName = side =>
  switch side {
  | ToJson => "ToJson"
  | FromJson => "FromJson"
  | ToCbor => "ToCbor"
  | FromCbor => "FromCbor"
  }

let function = side =>
  switch side {
  | ToJson => "toJson"
  | FromJson => "fromJson"
  | ToCbor => "toCbor"
  | FromCbor => "fromCbor"
  }

let primName = p =>
  switch p {
  | Bool => "bool"
  | String => "string"
  | Float64 => "float"
  | Int32 => "int"
  | Uint32 => "uint32"
  | Int53 => "int53"
  | Uint53 => "uint53"
  | Bytes | Secret => "bytes"
  | Hash => "hash"
  }

/** What the source names each type by: its module. */
type names = {modules: Map.t<string, string>}

let moduleOf = (names, name, at) =>
  switch names.modules->Map.get(name) {
  | Some(m) => m
  | None => fail(at, "a type declared")
  }

let rec typeOf = (names, shape, at) =>
  switch shape {
  | Prim(Bool) => "bool"
  | Prim(String) => "string"
  | Prim(Float64) => "float"
  | Prim(Int32) => "int"
  | Prim(Uint32 | Int53 | Uint53) | Id => "float"
  | Prim(Bytes | Hash | Secret) => "Uint8Array.t"
  | Type(name) => `${moduleOf(names, name, at)}.t`
  | List(s) => `array<${typeOf(names, s, at)}>`
  | Map(s) => `dict<${typeOf(names, s, at)}>`
  }

let rec coder = (names, side, shape, at) => {
  let wire = `Wire.${sideName(side)}`
  switch shape {
  | Prim(p) => `${wire}.${primName(p)}`
  | Id => `${wire}.uint32`
  | Type(name) =>
    let m = moduleOf(names, name, at)
    switch side {
    | ToJson | ToCbor => `${m}.${function(side)}`
    | FromJson | FromCbor => `${wire}.named(${m}.${function(side)})`
    }
  | List(s) => `${wire}.list(${coder(names, side, s, at)})`
  | Map(s) => `${wire}.map(${coder(names, side, s, at)})`
  }
}

/** A record's or a case's fields, checked: each name and key once, none of them `taken`. */
let checked = (fields: array<field>, at, ~taken: array<string>=[], ~keys: array<int>=[]) => {
  let at = i => [...at, Int.toString(i)]
  let labels = fields->Array.mapWithIndex((f, i) => label(f.name, [...at(i), "name"]))
  distinct(
    [...taken, ...fields->Array.map(f => f.name)],
    i => [...at(i - taken->Array.length), "name"],
    "a name no other field has",
  )
  distinct(labels, i => [...at(i), "name"], "a name no other field has in ReScript")
  distinct(
    [...keys, ...fields->Array.map(f => f.key)],
    i => [...at(i - keys->Array.length), "key"],
    "a key no other field has",
  )
  fields->Array.mapWithIndex((f, i) => (f, labels->Array.getUnsafe(i), at(i)))
}

let fieldTypes = (names, fields) =>
  fields
  ->Array.map(((f: field, label, at)) => {
    let annotation = label == f.name ? "" : `@as(${quote(f.name)}) `
    `${annotation}${label}${f.optional ? "?" : ""}: ${typeOf(names, f.shape, [...at, "shape"])}`
  })
  ->Array.join(", ")

/** Each field written, from `value`, as `side` writes it. */
let writes = (names, side, fields, value) =>
  fields
  ->Array.map(((f: field, label, at)) => {
    let name = switch side {
    | ToJson | FromJson => quote(f.name)
    | ToCbor | FromCbor => Int.toString(f.key)
    }
    let how = f.optional ? "optional" : "field"
    `Wire.${sideName(side)}.${how}(${name}, ${value}.${label}, ${coder(
        names,
        side,
        f.shape,
        [...at, "shape"],
      )})`
  })
  ->Array.join(", ")

/** Each field read, from the fields `o`, as `side` reads it, into a record's literal. */
let reads = (names, side, fields) =>
  fields
  ->Array.map(((f: field, label, at)) => {
    let key = switch side {
    | ToJson | FromJson => ""
    | ToCbor | FromCbor => `${Int.toString(f.key)}, `
    }
    let how = f.optional ? "optional" : "field"
    `${label}: ${f.optional ? "?" : ""}Wire.${sideName(side)}.${how}(o, ${key}${quote(
        f.name,
      )}, ${coder(names, side, f.shape, [...at, "shape"])})`
  })
  ->Array.join(", ")

/** A type's definition and its four functions, the definition apart, as a recursive module's
 * signature repeats it. */
let typeModule = (names, def, at) =>
  switch def {
  | Record(fields) =>
    let fields = checked(fields, [...at, "record"])
    let empty = fields->Array.length == 0
    let v = empty ? "_" : "v"
    let o = empty ? "_" : "o"
    let literal = empty ? "({}: t)" : `{${reads(names, FromJson, fields)}}`
    let literalCbor = empty ? "({}: t)" : `{${reads(names, FromCbor, fields)}}`
    (
      [`type t = {${fieldTypes(names, fields)}}`],
      [
        `let toJson = (${v}: t) => Wire.ToJson.record([${writes(names, ToJson, fields, "v")}])`,
        `let fromJson = json => Wire.FromJson.record(json, ${o} => ${literal})`,
        `let toCbor = (${v}: t) => Wire.ToCbor.record([${writes(names, ToCbor, fields, "v")}])`,
        `let fromCbor = cbor => Wire.FromCbor.record(cbor, ${o} => ${literalCbor})`,
      ],
    )
  | Enum(choices) =>
    let at = [...at, "enum"]
    let constructors =
      choices->Array.mapWithIndex((c, i) => upper(c.name, [...at, Int.toString(i), "name"]))
    distinct(constructors, i => [...at, Int.toString(i), "name"], "a name no other choice has")
    distinct(
      choices->Array.map(c => c.code),
      i => [...at, Int.toString(i), "code"],
      "a code no other choice has",
    )
    let each = f => choices->Array.mapWithIndex((c, i) => f(c, constructors->Array.getUnsafe(i)))
    let cases = f => each((c, k) => `| ${k} => ${f(c)}`)->Array.join(" ")
    (
      [`type t = ${each((c, k) => `| @as(${quote(c.name)}) ${k}`)->Array.join(" ")}`],
      [
        `let toJson = (v: t) => switch v { ${cases(c => `Wire.ToJson.string(${quote(c.name)})`)} }`,
        `let fromJson = json => Wire.FromJson.choice(json, [${each((c, k) =>
            `(${quote(c.name)}, ${k})`
          )->Array.join(", ")}])`,
        `let toCbor = (v: t) => switch v { ${cases(c =>
            `Wire.ToCbor.int(${Int.toString(c.code)})`
          )} }`,
        `let fromCbor = cbor => Wire.FromCbor.choice(cbor, [${each((c, k) =>
            `(${Int.toString(c.code)}, ${k})`
          )->Array.join(", ")}])`,
      ],
    )
  | Flags(choices) =>
    let at = [...at, "flags"]
    let constructors =
      choices->Array.mapWithIndex((c, i) => upper(c.name, [...at, Int.toString(i), "name"]))
    distinct(constructors, i => [...at, Int.toString(i), "name"], "a name no other choice has")
    distinct(
      choices->Array.map(c => c.code),
      i => [...at, Int.toString(i), "code"],
      "a code no other choice has",
    )
    choices->Array.forEachWithIndex((c, i) =>
      if c.code <= 0 || (c.code &&& c.code - 1) != 0 {
        fail([...at, Int.toString(i), "code"], "a power of two")
      }
    )
    let each = f => choices->Array.mapWithIndex((c, i) => f(c, constructors->Array.getUnsafe(i)))
    let table = f => `[${each(f)->Array.join(", ")}]`
    let byName = table((c, k) => `(${quote(c.name)}, ${k})`)
    let byCode = table((c, k) => `(${Int.toString(c.code)}, ${k})`)
    (
      [
        `type name = ${each((c, k) => `| @as(${quote(c.name)}) ${k}`)->Array.join(" ")}`,
        "type t = array<name>",
      ],
      [
        `let toJson = (v: t) => Wire.ToJson.flags(v, ${byName})`,
        `let fromJson = json => Wire.FromJson.flags(json, ${byName})`,
        `let toCbor = (v: t) => Wire.ToCbor.flags(v, ${byCode})`,
        `let fromCbor = cbor => Wire.FromCbor.flags(cbor, ${byCode})`,
      ],
    )
  | Union({tag, cases}) =>
    let at = [...at, "union"]
    let constructors =
      cases->Array.mapWithIndex((c, i) => upper(c.name, [...at, "cases", Int.toString(i), "name"]))
    distinct(
      constructors,
      i => [...at, "cases", Int.toString(i), "name"],
      "a name no other case has",
    )
    distinct(
      cases->Array.map(c => c.code),
      i => [...at, "cases", Int.toString(i), "code"],
      "a code no other case has",
    )
    let each = f =>
      cases->Array.mapWithIndex((c, i) => {
        let fields = checked(
          c.fields,
          [...at, "cases", Int.toString(i), "fields"],
          ~taken=[tag],
          ~keys=[0],
        )
        f(c, constructors->Array.getUnsafe(i), fields)
      })
    let held = cases->Array.some(c => c.fields->Array.length > 0)
    let o = held ? "o" : "_"
    let written = (side, c: case, fields) => {
      let fields = writes(names, side, fields, "c")
      switch side {
      | ToJson | FromJson => `Wire.ToJson.case(${quote(tag)}, ${quote(c.name)}, [${fields}])`
      | ToCbor | FromCbor => `Wire.ToCbor.case(${Int.toString(c.code)}, [${fields}])`
      }
    }
    let toSide = side =>
      each((c, k, fields) =>
        `| ${k}${fields->Array.length > 0 ? "(c)" : ""} => ${written(side, c, fields)}`
      )->Array.join(" ")
    let fromSide = side =>
      each((c, k, fields) => {
        let matched = switch side {
        | FromJson | ToJson => quote(c.name)
        | FromCbor | ToCbor => Int.toString(c.code)
        }
        let built = fields->Array.length > 0 ? `${k}({${reads(names, side, fields)}})` : k
        `| ${matched} => ${built}`
      })->Array.join(" ")
    let caseNames = cases->Array.map(c => quote(c.name))->Array.join(", ")
    let codes = cases->Array.map(c => Int.toString(c.code))->Array.join(", ")
    (
      [
        `@tag(${quote(tag)}) type t = ${each((c, k, fields) =>
            `| @as(${quote(c.name)}) ${k}${fields->Array.length > 0
                ? `({${fieldTypes(names, fields)}})`
                : ""}`
          )->Array.join(" ")}`,
      ],
      [
        `let toJson = (v: t) => switch v { ${toSide(ToJson)} }`,
        `let fromJson = json => Wire.FromJson.union(json, ${quote(
            tag,
          )}, (name, ${o}) => switch name { ${fromSide(
            FromJson,
          )} | _ => Wire.FromJson.unknown(${quote(tag)}, [${caseNames}]) })`,
        `let toCbor = (v: t) => switch v { ${toSide(ToCbor)} }`,
        `let fromCbor = cbor => Wire.FromCbor.union(cbor, ${quote(
            tag,
          )}, (code, ${o}) => switch code { ${fromSide(
            FromCbor,
          )} | _ => Wire.FromCbor.unknown(${quote(tag)}, [${codes}]) })`,
      ],
    )
  }

let signature = [
  "let toJson: t => JSON.t",
  "let fromJson: JSON.t => result<t, Malformed.t>",
  "let toCbor: t => Codec.Cbor.value",
  "let fromCbor: Codec.Cbor.value => result<t, Malformed.t>",
]

/** The types each type's fields name. */
let rec named = shape =>
  switch shape {
  | Prim(_) | Id => []
  | Type(name) => [name]
  | List(s) | Map(s) => named(s)
  }

let refers = def =>
  switch def {
  | Record(fields) => fields->Array.flatMap(f => named(f.shape))
  | Union({cases}) => cases->Array.flatMap(c => c.fields->Array.flatMap(f => named(f.shape)))
  | Enum(_) | Flags(_) => []
  }

/**
 * The types in groups each written before those that name it, a group the types that name one
 * another, Tarjan's: in the contracts' order, so the same for the same contracts.
 */
let groups = (types: array<(string, def)>) => {
  let order = Map.fromArray(types->Array.mapWithIndex(((name, _), i) => (name, i)))
  let edges = types->Array.map(((_, def)) => refers(def)->Array.filterMap(n => order->Map.get(n)))
  let index = Array.make(~length=types->Array.length, -1)
  let low = Array.make(~length=types->Array.length, 0)
  let onStack = Array.make(~length=types->Array.length, false)
  let stack = []
  let next = ref(0)
  let found = []
  let rec visit = v => {
    index->Array.setUnsafe(v, next.contents)
    low->Array.setUnsafe(v, next.contents)
    next := next.contents + 1
    stack->Array.push(v)
    onStack->Array.setUnsafe(v, true)
    edges
    ->Array.getUnsafe(v)
    ->Array.forEach(w =>
      if index->Array.getUnsafe(w) < 0 {
        visit(w)
        low->Array.setUnsafe(v, Math.Int.min(low->Array.getUnsafe(v), low->Array.getUnsafe(w)))
      } else if onStack->Array.getUnsafe(w) {
        low->Array.setUnsafe(v, Math.Int.min(low->Array.getUnsafe(v), index->Array.getUnsafe(w)))
      }
    )
    if low->Array.getUnsafe(v) == index->Array.getUnsafe(v) {
      let group = []
      let go = ref(true)
      while go.contents {
        switch stack->Array.pop {
        | Some(w) =>
          onStack->Array.setUnsafe(w, false)
          group->Array.push(w)
          go := w != v
        | None => go := false
        }
      }
      group->Array.sort((a, b) => Int.compare(a, b))
      let recursive = group->Array.length > 1 || edges->Array.getUnsafe(v)->Array.includes(v)
      found->Array.push((group->Array.map(i => types->Array.getUnsafe(i)), recursive))
    }
  }
  types->Array.forEachWithIndex((_, v) =>
    if index->Array.getUnsafe(v) < 0 {
      visit(v)
    }
  )
  found
}

/** What each of a call's fields holds. */
type role = InterfaceName | OperationName | OperationInput | Capabilities

/**
 * A call's fields by what each holds, in the contracts' order: its interface's name and its
 * operation's, each a string; that operation's input; and the capabilities, an optional list of
 * bytes; each once.
 */
let roles = (fields: array<callField>) => {
  let at = ["call", "fields"]
  let operation = switch fields->Array.filterMap(f =>
    switch f.shape {
    | Input(operation) => Some(operation)
    | Shape(_) => None
    }
  ) {
  | [operation] => operation
  | _ => fail(at, "one field holding an operation's input")
  }
  let roles = fields->Array.mapWithIndex((f, i) => {
    let refused = () =>
      fail(
        [...at, Int.toString(i)],
        "the interface's name or the operation's, a string; its input; or the capabilities, an optional list of bytes",
      )
    let role = switch f.shape {
    | Input(_) => f.optional ? refused() : OperationInput
    | Shape(Prim(String)) =>
      f.optional ? refused() : f.name == operation ? OperationName : InterfaceName
    | Shape(List(Prim(Bytes))) => f.optional ? Capabilities : refused()
    | Shape(Prim(Bool | Float64 | Int32 | Uint32 | Int53 | Uint53 | Bytes | Hash | Secret))
    | Shape(Id | Type(_) | Map(_))
    | Shape(List(Prim(Bool | String | Float64 | Int32 | Uint32 | Int53 | Uint53 | Hash | Secret)))
    | Shape(List(Id | Type(_) | List(_) | Map(_))) =>
      refused()
    }
    (f, role)
  })
  let one = role =>
    switch roles->Array.filter(((_, r)) => r == role) {
    | [(f, _)] => f
    | _ =>
      fail(at, "the interface's name, the operation's, its input and the capabilities, each once")
    }
  (roles, one(InterfaceName), one(OperationName), one(OperationInput), one(Capabilities))
}

let rescript = (contracts: contracts) =>
  caught(() => {
    let modules =
      contracts.types->Array.mapWithIndex(((name, _), _) => upper(name, ["types", name]))
    modules->Array.forEachWithIndex((m, i) => {
      let (name, _) = contracts.types->Array.getUnsafe(i)
      if reserved->Array.includes(m) || modules->Array.slice(~start=0, ~end=i)->Array.includes(m) {
        fail(["types", name], "a name whose module no other has")
      }
    })
    let names = {
      modules: Map.fromArray(
        contracts.types->Array.mapWithIndex(((name, _), i) => (name, modules->Array.getUnsafe(i))),
      ),
    }
    let lines = [
      "/***\n * Written by envelope-generator from `model/contracts.json`, `model/graph/tools.res`: what\n * `src/malformed.resi` says this module holds. Never edited; `mise run generate` writes it again.\n */",
    ]
    groups(contracts.types)->Array.forEach(((group, recursive)) =>
      if recursive {
        group->Array.forEachWithIndex(
          ((name, def), i) => {
            let (types, functions) = typeModule(names, def, ["types", name])
            let m = moduleOf(names, name, [])
            lines->Array.push(
              `${i == 0 ? "module rec" : "and"} ${m}: { ${[...types, ...signature]->Array.join(
                  "\n",
                )} } = { ${[...types, ...functions]->Array.join("\n")} }`,
            )
          },
        )
      } else {
        group->Array.forEach(
          ((name, def)) => {
            let (types, functions) = typeModule(names, def, ["types", name])
            lines->Array.push(
              `module ${moduleOf(names, name, [])} = { ${[...types, ...functions]->Array.join(
                  "\n",
                )} }`,
            )
          },
        )
      }
    )
    let (types, functions) = typeModule({modules: Map.make()}, Record(contracts.shell), ["shell"])
    lines->Array.push(`module Shell = { ${[...types, ...functions]->Array.join("\n")} }`)
    // The reasons, their failure a choice of the type `failure`.
    let failures = switch contracts.types->Array.find(((name, _)) => name == "failure") {
    | Some((_, Enum(choices))) => choices->Array.map(c => c.name)
    | Some((_, Record(_) | Union(_) | Flags(_))) | None =>
      fail(["types", "failure"], "an enumeration, the failures a reason is one of")
    }
    let reason = (r: reason, at) => {
      if !(failures->Array.includes(r.failure)) {
        fail([...at, "failure"], `one of ${failures->Array.join(", ")}`)
      }
      `{name: ${quote(r.name)}, failure: Failure.${upper(r.failure, [...at, "failure"])}}`
    }
    let reasons = (rs, at) =>
      `[${rs->Array.mapWithIndex((r, i) => reason(r, [...at, Int.toString(i)]))->Array.join(", ")}]`
    lines->Array.pushMany([
      "type reason = {name: string, failure: Failure.t}",
      "type operation = {interface: string, version: int, name: string, input: string, output: string, reasons: array<reason>}",
      `let reasons: array<reason> = ${reasons(contracts.reasons, ["reasons"])}`,
      `let calling: array<reason> = ${reasons(contracts.calling, ["calling"])}`,
    ])
    let (callFields, interfaceField, operationField, inputField, capabilitiesField) = roles(
      contracts.call,
    )
    // Within `Interface`, a module of an interface's hides any of the same name the rest names.
    let named =
      contracts.interfaces->Array.flatMap(i =>
        i.operations->Array.mapWithIndex(
          (o, k) =>
            moduleOf(
              names,
              o.input,
              ["interfaces", i.name, "operations", Int.toString(k), "input"],
            ),
        )
      )
    let interfaces = contracts.interfaces->Array.map(i => {
      let at = ["interfaces", i.name]
      let m = upper(i.name, at)
      if m == "Failure" || reserved->Array.includes(m) || named->Array.includes(m) {
        fail(at, "a name whose module hides no type's this module names")
      }
      if i.operations->Array.length == 0 {
        fail([...at, "operations"], "an operation at least")
      }
      let values =
        i.operations->Array.mapWithIndex(
          (o, n) => lower(o.name, [...at, "operations", Int.toString(n), "name"]),
        )
      let own = ["version", "toJson", "fromJson", "toCbor", "fromCbor"]
      distinct(
        [...own, ...values],
        n => [...at, "operations", Int.toString(n - own->Array.length), "name"],
        "a name no other operation has, nor version, toJson, fromJson, toCbor or fromCbor",
      )
      let constructors =
        i.operations->Array.mapWithIndex(
          (o, n) => upper(o.name, [...at, "operations", Int.toString(n), "name"]),
        )
      distinct(
        constructors,
        n => [...at, "operations", Int.toString(n), "name"],
        "a name no other operation has in upper camel case",
      )
      let each = f =>
        i.operations
        ->Array.mapWithIndex(
          (o, n) => f(o, constructors->Array.getUnsafe(n), moduleOf(names, o.input, [])),
        )
        ->Array.join(" ")
      let isJson = side =>
        switch side {
        | ToJson | FromJson => true
        | ToCbor | FromCbor => false
        }
      let refer = (side, f: callField) =>
        isJson(side) ? quote(f.name) : `${Int.toString(f.key)}, ${quote(f.name)}`
      let written = side => {
        let w = `Wire.${sideName(side)}`
        let items = callFields->Array.map(
          ((f, role)) => {
            let name = isJson(side) ? quote(f.name) : Int.toString(f.key)
            switch role {
            | InterfaceName => `${w}.field(${name}, ${quote(i.name)}, ${w}.string)`
            | OperationName => `${w}.field(${name}, operation, ${w}.string)`
            | OperationInput => `${w}.field(${name}, input, ${w}.${isJson(side) ? "json" : "cbor"})`
            | Capabilities =>
              `${w}.optional(${name}, Wire.nonEmpty(v.capabilities), ${w}.list(${w}.bytes))`
            }
          },
        )
        `let ${function(side)} = (v: envelope) => { let (operation, input) = switch v.call { ${each(
            (o, k, m) => `| ${k}(input) => (${quote(o.name)}, ${m}.${function(side)}(input))`,
          )} }
${w}.record([${items->Array.join(", ")}]) }`
      }
      let read = side => {
        let w = `Wire.${sideName(side)}`
        let value = isJson(side) ? "json" : "cbor"
        let unknown = isJson(side) ? "unknown" : "unknownText"
        let names_ = i.operations->Array.map(o => quote(o.name))->Array.join(", ")
        `let ${function(side)} = ${value} => ${w}.record(${value}, o => { ${w}.field(o, ${refer(
            side,
            interfaceField,
          )}, ${w}.exactly(${quote(i.name)}))->ignore
let call = switch ${w}.field(o, ${refer(side, operationField)}, ${w}.string) { ${each(
            (o, k, m) =>
              `| ${quote(o.name)} => ${k}(${w}.field(o, ${refer(
                  side,
                  inputField,
                )}, ${w}.named(${m}.${function(side)})))`,
          )} | _ => ${w}.${unknown}(${quote(operationField.name)}, [${names_}]) }
{call, capabilities: Wire.orEmpty(${w}.optional(o, ${refer(
            side,
            capabilitiesField,
          )}, ${w}.list(${w}.bytes)))} })`
      }
      let call = [
        `type call = ${each((_, k, m) => `| ${k}(${m}.t)`)}`,
        "type envelope = {call: call, capabilities: array<Uint8Array.t>}",
        written(ToJson),
        read(FromJson),
        written(ToCbor),
        read(FromCbor),
      ]
      let operations = i.operations->Array.mapWithIndex(
        (o, n) => {
          let at = [...at, "operations", Int.toString(n)]
          let _: string = moduleOf(names, o.input, [...at, "input"])
          let _: string = moduleOf(names, o.output, [...at, "output"])
          `let ${values->Array.getUnsafe(n)}: operation = {interface: ${quote(
              i.name,
            )}, version: ${Int.toString(i.version)}, name: ${quote(o.name)}, input: ${quote(
              o.input,
            )}, output: ${quote(o.output)}, reasons: ${reasons(o.reasons, [...at, "reasons"])}}`
        },
      )
      `module ${m} = { let version = ${Int.toString(i.version)}\n${[
          ...operations,
          ...call,
        ]->Array.join("\n")} }`
    })
    distinct(
      contracts.interfaces->Array.map(i => upper(i.name, ["interfaces", i.name])),
      n => ["interfaces", (contracts.interfaces->Array.getUnsafe(n)).name],
      "a name whose module no other interface has",
    )
    lines->Array.push(`module Interface = { ${interfaces->Array.join("\n")} }`)
    let byName = (f, (name, _)) =>
      `| ${quote(name)} => Some(${f(moduleOf(names, name, ["types", name]))})`
    let switched = f =>
      `switch name { ${contracts.types
        ->Array.map(t => byName(f, t))
        ->Array.join(" ")} | _ => None }`
    let calls = f =>
      `switch interface { ${contracts.interfaces
        ->Array.map(i =>
          `| ${quote(i.name)} => Some(${f(`Interface.${upper(i.name, ["interfaces", i.name])}`)})`
        )
        ->Array.join(" ")} | _ => None }`
    lines->Array.pushMany([
      `let callJsonToCbor = (interface, json) => ${calls(m =>
          `Wire.jsonToCbor(json, ${m}.fromJson, ${m}.toCbor)`
        )}`,
      `let callCborToJson = (interface, cbor) => ${calls(m =>
          `Wire.cborToJson(cbor, ${m}.fromCbor, ${m}.toJson)`
        )}`,
    ])
    lines->Array.pushMany([
      `let jsonToCbor = (name, json) => ${switched(m =>
          `Wire.jsonToCbor(json, ${m}.fromJson, ${m}.toCbor)`
        )}`,
      `let cborToJson = (name, cbor) => ${switched(m =>
          `Wire.cborToJson(cbor, ${m}.fromCbor, ${m}.toJson)`
        )}`,
    ])
    lines->Array.join("\n\n") ++ "\n"
  })
