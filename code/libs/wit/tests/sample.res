/*** The samples read as they stand from their paths, JSON through `JSON.Decode`. */

/** A file at `path`, from the repository's root. */
let text = path => Node.readFileSync(Node.fromRoot(path))

let read = path => text(path)->JSON.parseOrThrow

let fail = (json, what) => JsError.throwWithMessage(`${JSON.stringify(json)}: ${what}`)

/** A member of a JSON object, if it is one and has it. */
let member = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))

/** A member that must be there, by a path of names. */
let at = (json, names) =>
  names->Array.reduce(json, (json, name) =>
    switch member(json, name) {
    | Some(value) => value
    | None => fail(json, `no ${name}`)
    }
  )

let string = json =>
  switch json->JSON.Decode.string {
  | Some(text) => text
  | None => fail(json, "no string")
  }

let int = json =>
  switch json->JSON.Decode.float {
  | Some(n) => Float.toInt(n)
  | None => fail(json, "no number")
  }

let items = json =>
  switch json->JSON.Decode.array {
  | Some(items) => items
  | None => fail(json, "no array")
  }

/** A member that may be absent or null. */
let optional = (json, name, decode) =>
  switch member(json, name) {
  | Some(value) if value != JSON.Null => Some(decode(value))
  | Some(_) | None => None
  }

/** A file of a refused case, its lines joined by a newline and ending in one. */
let lines = json => json->at(["lines"])->items->Array.map(string)->Array.join("\n") ++ "\n"

let primitives: array<World.primitive> = [
  #bool,
  #s8,
  #s16,
  #s32,
  #s64,
  #u8,
  #u16,
  #u32,
  #u64,
  #f32,
  #f64,
  #char,
  #string,
]

/** A type as the samples write it, a primitive by its keyword and any other by its one word. */
let rec type_ = (json): World.type_ =>
  switch json->JSON.Decode.string {
  | Some(word) =>
    switch primitives->Array.find(p => (p :> string) == word) {
    | Some(p) => Primitive(p)
    | None => fail(json, "no primitive")
    }
  | None =>
    let has = name => member(json, name) != None
    if has("list") {
      List(json->at(["list"])->type_)
    } else if has("option") {
      Option(json->at(["option"])->type_)
    } else if has("tuple") {
      Tuple(json->at(["tuple"])->items->Array.map(type_))
    } else if has("result") {
      let r = json->at(["result"])
      Result({success: r->optional("success", type_), failure: r->optional("failure", type_)})
    } else if has("record") {
      Record({
        name: json->at(["record"])->string,
        fields: json
        ->at(["fields"])
        ->items
        ->Array.map((f): World.field => {
          name: f->at(["name"])->string,
          type_: f->at(["type"])->type_,
        }),
      })
    } else if has("variant") {
      Variant({
        name: json->at(["variant"])->string,
        cases: json
        ->at(["cases"])
        ->items
        ->Array.map((c): World.case => {
          label: c->at(["name"])->string,
          payload: c->optional("payload", type_),
        }),
      })
    } else if has("enum") {
      Enum({name: json->at(["enum"])->string, cases: json->at(["cases"])->items->Array.map(string)})
    } else if has("flags") {
      Flags({
        name: json->at(["flags"])->string,
        flags: json->at(["names"])->items->Array.map(string),
      })
    } else {
      fail(json, "no type")
    }
  }

let function = (json): World.function => {
  name: json->at(["name"])->string,
  parameters: json
  ->at(["parameters"])
  ->items
  ->Array.map((p): World.parameter => {
    name: p->at(["name"])->string,
    type_: p->at(["type"])->type_,
  }),
  result: json->optional("result", type_),
}

let package = (json): option<World.package> =>
  json
  ->optional("package", p => p)
  ->Option.map(p => {
    World.namespace: p->at(["namespace"])->string,
    name: p->at(["name"])->string,
    version: p->optional("version", string),
  })

let construct = (json): World.construct =>
  switch (json->JSON.Decode.string, member(json, "foreign"), member(json, "beyond")) {
  | (Some("resource"), None, None) => Resource
  | (Some("own"), None, None) => Own
  | (Some("borrow"), None, None) => Borrow
  | (Some("include"), None, None) => Include
  | (None, Some(path), None) => Foreign(string(path))
  | (None, None, Some(word)) => Beyond(string(word))
  | _ => fail(json, "no construct")
  }

/** A problem, a word where it carries nothing and an object of one word where it does. */
let problem = (json): World.problem =>
  switch json->JSON.Decode.string {
  | Some("nested") => Nested
  | Some("no world") => NoWorld
  | Some("second world") => SecondWorld
  | Some(_) => fail(json, "no problem")
  | None =>
    let one = (name, make) => member(json, name)->Option.map(make)
    let found = [
      one("refused", c => World.Refused(construct(c))),
      one("unexpected", found => World.Unexpected({
        found: found->JSON.Decode.string,
        expected: json->at(["expected"])->string,
      })),
      one("name", n => World.Name(string(n))),
      one("character", c => World.Character(int(c))),
      one("undefined", n => World.Undefined(string(n))),
      one("repeated", n => World.Repeated(string(n))),
      one("recursive", n => World.Recursive(string(n))),
    ]->Array.filterMap(p => p)
    switch found {
    | [problem] => problem
    | _ => fail(json, "no one problem")
    }
  }

let refusal = (json): World.refusal => {
  problem: json->at(["problem"])->problem,
  line: json->at(["line"])->int,
  column: json->at(["column"])->int,
}

/** A step, its word and then its name or its position. */
let step = (json): World.step => {
  let text = string(json)
  let rest = word => text->String.slice(~start=String.length(word) + 1)
  let number = word => rest(word)->Int.fromString->Option.getOr(-1)
  switch text->String.split(" ")->Array.get(0) {
  | Some("parameter") => Parameter(number("parameter"))
  | Some("result") => Returned
  | Some("field") => Field(rest("field"))
  | Some("case") => Case(rest("case"))
  | Some("element") => Element
  | Some("item") => Item(number("item"))
  | Some("present") => Present
  | Some("success") => Success
  | Some("failure") => Failure
  | _ => fail(json, "no step")
  }
}

let mismatch = (json): World.mismatch => {
  let steps = () => json->at(["at"])->items->Array.map(step)
  switch (
    member(json, "undeclared"),
    member(json, "missing"),
    member(json, "count"),
    member(json, "mistyped"),
    member(json, "unheld"),
  ) {
  | (Some(call), None, None, None, None) => Undeclared(string(call))
  | (None, Some(call), None, None, None) => Missing(string(call))
  | (None, None, Some(call), None, None) =>
    Count({
      call: string(call),
      caller: json->at(["caller"])->int,
      export: json->at(["export"])->int,
    })
  | (None, None, None, Some(call), None) => Mistyped({call: string(call), at: steps()})
  | (None, None, None, None, Some(call)) =>
    Unheld({call: string(call), at: steps(), case: json->at(["case"])->string})
  | _ => fail(json, "no one mismatch")
  }
}
