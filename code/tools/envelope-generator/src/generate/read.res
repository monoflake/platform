/***
 * `model/contracts.json` read into its `Model.contracts`, each value by its path from the top.
 * `read.rs` beside it is the same in Rust.
 */
open Model

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

/**
 * The answer, its two cases `success`, holding one field of the operation's output, and `error`,
 * holding a type, in that order.
 */
let answer = (json, at) => {
  let o = object(json, at)
  let cases = [...at, "cases"]
  let case = (json, i, name) => {
    let at = [...cases, Int.toString(i)]
    let o = object(json, at)
    if text(member(o, at, "name"), [...at, "name"]) != name {
      fail([...at, "name"], name)
    }
    (o, at, integer(member(o, at, "code"), [...at, "code"]))
  }
  switch member(o, at, "cases")->JSON.Decode.array {
  | Some([success, error]) =>
    let (s, sAt, sCode) = case(success, 0, "success")
    let data = switch member(s, sAt, "fields")->JSON.Decode.array {
    | Some([data]) =>
      let fAt = [...sAt, "fields", "0"]
      let f = object(data, fAt)
      let shape = object(member(f, fAt, "shape"), [...fAt, "shape"])
      if shape->Dict.get("output")->Option.flatMap(JSON.Decode.string) != Some("operation") {
        fail([...fAt, "shape"], "the operation's output")
      }
      if optional(f, fAt) {
        fail([...fAt, "optional"], "a field present")
      }
      (
        text(member(f, fAt, "name"), [...fAt, "name"]),
        integer(member(f, fAt, "key"), [...fAt, "key"]),
      )
    | Some(_) | None => fail([...sAt, "fields"], "one field, the operation's output")
    }
    let (e, eAt, eCode) = case(error, 1, "error")
    let (name, key) = data
    {
      tag: text(member(o, at, "tag"), [...at, "tag"]),
      success: (sCode, name, key),
      error: (eCode, text(member(e, eAt, "type"), [...eAt, "type"])),
    }
  | Some(_) | None => fail(cases, "two cases, success and error")
  }
}

/** A reason's default message, read where `read`'s own text hides `text`. */
let message = text

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
      answer: answer(member(o, [], "answer"), ["answer"]),
      messages: entries(member(o, [], "messages"), ["messages"], message),
      interfaces: entries(member(o, [], "interfaces"), ["interfaces"], (json, at) =>
        interface_(at->Array.at(-1)->Option.getOr(""), json, at)
      )->Array.map(((_, i)) => i),
    }
  })
