/***
 * What the source is written with: each type's module and its four functions, the groups types
 * that name one another are written in, a call's fields by what each holds, and `Answer`.
 */
open Model
open Names

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

/**
 * `Answer`: a union by its tag, `Success` holding the output, written and read by the functions
 * given, and `Error` the fields of the type its case names, a record, beside the tag.
 */
let answerModule = (names, contracts: contracts) => {
  let {tag, success: (successCode, data, dataKey), error: (errorCode, errorType)} = contracts.answer
  let typeAt = ["answer", "cases", "1", "type"]
  let errorModule = moduleOf(names, errorType, typeAt)
  let fields = switch contracts.types->Array.find(((name, _)) => name == errorType) {
  | Some((name, Record(fields))) =>
    checked(fields, ["types", name, "record"], ~taken=[tag], ~keys=[0])
  | Some((_, Enum(_) | Union(_) | Flags(_))) | None => fail(typeAt, "a record")
  }
  if dataKey == 0 || data == tag {
    fail(
      ["answer", "cases", "0", "fields", "0"],
      "a field other than the tag, at a key other than 0",
    )
  }
  if successCode == errorCode {
    fail(["answer", "cases", "1", "code"], "a code other than success's")
  }
  let t = quote(tag)
  let built = side => `{${reads(names, side, fields)}}`
  let parts = [
    `type t<'output> = Success('output) | Error(${errorModule}.t)`,
    `let toJson = (v, data) => switch v { | Success(d) => Wire.ToJson.case(${t}, "success", [Wire.ToJson.field(${quote(
        data,
      )}, d, data)]) | Error(c) => Wire.ToJson.case(${t}, "error", [${writes(
        names,
        ToJson,
        fields,
        "c",
      )}]) }`,
    `let fromJson = (json, data) => Wire.FromJson.union(json, ${t}, (name, o) => switch name { | "success" => Success(Wire.FromJson.field(o, ${quote(
        data,
      )}, Wire.FromJson.named(data))) | "error" => Error(${built(
        FromJson,
      )}) | _ => Wire.FromJson.unknown(${t}, ["success", "error"]) })`,
    `let toCbor = (v, data) => switch v { | Success(d) => Wire.ToCbor.case(${Int.toString(
        successCode,
      )}, [Wire.ToCbor.field(${Int.toString(
        dataKey,
      )}, d, data)]) | Error(c) => Wire.ToCbor.case(${Int.toString(errorCode)}, [${writes(
        names,
        ToCbor,
        fields,
        "c",
      )}]) }`,
    `let fromCbor = (cbor, data) => Wire.FromCbor.union(cbor, ${t}, (code, o) => switch code { | ${Int.toString(
        successCode,
      )} => Success(Wire.FromCbor.field(o, ${Int.toString(dataKey)}, ${quote(
        data,
      )}, Wire.FromCbor.named(data))) | ${Int.toString(errorCode)} => Error(${built(
        FromCbor,
      )}) | _ => Wire.FromCbor.unknown(${t}, [${Int.toString(successCode)}, ${Int.toString(
        errorCode,
      )}]) })`,
  ]
  `module Answer = { ${parts->Array.join("\n")} }`
}
