/***
 * A file's world resolved from what `Syntax` parsed, every alias followed, and calls matched
 * against exports by their types alone, kd7f9.
 */

type primitive = Lexer.primitive

type rec type_ =
  | Primitive(primitive)
  | List(type_)
  | Option(type_)
  | Tuple(array<type_>)
  | Result({success: option<type_>, failure: option<type_>})
  | Record({name: string, fields: array<field>})
  | Variant({name: string, cases: array<case>})
  | Enum({name: string, cases: array<string>})
  | Flags({name: string, flags: array<string>})
and field = {name: string, type_: type_}
and case = {label: string, payload: option<type_>}

type parameter = {name: string, type_: type_}

type function = {name: string, parameters: array<parameter>, result: option<type_>}

type package = Syntax.package = {namespace: string, name: string, version: option<string>}

type t = {
  package: option<package>,
  name: string,
  imports: array<function>,
  exports: array<function>,
}

type construct = Lexer.construct =
  | Resource
  | Own
  | Borrow
  | Include
  | Foreign(string)
  | Beyond(string)

type problem = Lexer.problem =
  | Refused(construct)
  | Unexpected({found: option<string>, expected: string})
  | Name(string)
  | Character(int)
  | Undefined(string)
  | Repeated(string)
  | Recursive(string)
  | Nested
  | NoWorld
  | SecondWorld

type refusal = Lexer.refusal = {problem: problem, line: int, column: int}

/** Every value present, or none where one is absent. */
let all = values =>
  values->Array.every(Option.isSome) ? Some(values->Array.filterMap(v => v)) : None

/** Whether a type is an option, which no option may hold, vr5lw. */
let nests = t =>
  switch t {
  | Option(_) => true
  | Primitive(_)
  | List(_)
  | Tuple(_)
  | Result(_)
  | Record(_)
  | Variant(_)
  | Enum(_)
  | Flags(_) => false
  }

/** A name's type once resolved, kept apart from none so a failure is kept too. */
type resolution = Known(type_) | Failed

/** The world of a parsed file, every problem of resolving it pushed to `refusals`. */
let resolve = (file: Syntax.file, world: Syntax.world, refusals) => {
  let refuse = (problem, place: Lexer.place) =>
    refusals->Array.push({problem, line: place.line, column: place.column})
  let resolved: Map.t<string, resolution> = Map.make()
  let visiting: Set.t<string> = Set.make()
  let rec named = (scope: Syntax.scope, name, place: Lexer.place) => {
    let key = `${scope.id}\n${name}`
    switch (resolved->Map.get(key), scope.types->Map.get(name)) {
    | (Some(Known(t)), _) => Some(t)
    | (Some(Failed), _) => None
    | (None, _) if visiting->Set.has(key) =>
      refuse(Recursive(name), place)
      None
    | (None, None) =>
      refuse(Undefined(name), place)
      None
    | (None, Some((entry, defined))) =>
      visiting->Set.add(key)
      let t = switch entry {
      | Defines(definition) => define(scope, name, definition)
      | Uses({interface, original}) =>
        file.interfaces->Map.get(interface.name)->Option.flatMap(i => named(i, original, defined))
      | Elsewhere => None
      }
      visiting->Set.delete(key)->ignore
      resolved->Map.set(key, t->Option.mapOr(Failed, t => Known(t)))
      t
    }
  }
  and define = (scope, name, definition: Syntax.definition) =>
    switch definition {
    | Alias(t) => ty(scope, t)
    | RecordOf(fields) =>
      fields
      ->Array.map(((f, t)) => ty(scope, t)->Option.map((type_): field => {name: f.name, type_}))
      ->all
      ->Option.map(fields => Record({name, fields}))
    | VariantOf(cases) =>
      cases
      ->Array.map(((c, payload)) =>
        switch payload {
        | Some(t) => ty(scope, t)->Option.map(t => {label: c.name, payload: Some(t)})
        | None => Some({label: c.name, payload: None})
        }
      )
      ->all
      ->Option.map(cases => Variant({name, cases}))
    | EnumOf(cases) => Some(Enum({name, cases: cases->Array.map(c => c.name)}))
    | FlagsOf(flags) => Some(Flags({name, flags: flags->Array.map(f => f.name)}))
    | Opaque => None
    }
  and ty = (scope, t: Reader.ty) =>
    switch t {
    | Primitive(p) => Some(Primitive(p))
    | Named(name, place) => named(scope, name, place)
    | ListOf(t) => ty(scope, t)->Option.map(t => List(t))
    | OptionOf(t, place) =>
      switch ty(scope, t) {
      | Some(t) if nests(t) =>
        refuse(Nested, place)
        None
      | Some(t) => Some(Option(t))
      | None => None
      }
    | TupleOf(items) => items->Array.map(t => ty(scope, t))->all->Option.map(items => Tuple(items))
    | ResultOf(success, failure) =>
      let payload = t => t->Option.map(t => ty(scope, t))
      switch (payload(success), payload(failure)) {
      | (Some(None), _) | (_, Some(None)) => None
      | (success, failure) =>
        Some(
          Result({
            success: success->Option.flatMap(t => t),
            failure: failure->Option.flatMap(t => t),
          }),
        )
      }
    | Refused => None
    }
  let signature = (scope, prefix, (n: Reader.named, f: Syntax.signature)) => {
    let parameters =
      f.parameters
      ->Array.map(((p, t)) => ty(scope, t)->Option.map((type_): parameter => {name: p.name, type_}))
      ->all
    let result = f.result->Option.map(t => ty(scope, t))
    switch (parameters, result) {
    | (Some(parameters), Some(Some(_)) | None) =>
      Some({name: prefix ++ n.name, parameters, result: result->Option.flatMap(t => t)})
    | (None, _) | (_, Some(None)) => None
    }
  }
  let scopes = file.interfaces->Map.values->Array.fromIterator->Array.concat([world.scope])
  scopes->Array.forEach(scope => {
    scope.used->Array.forEach(i =>
      if !(file.interfaces->Map.has(i.name)) {
        refuse(Undefined(i.name), i.place)
      }
    )
    scope.types->Map.forEachWithKey(((_, place), name) => named(scope, name, place)->ignore)
  })
  let functions = Map.make()
  file.interfaces->Map.forEachWithKey((scope, i) =>
    functions->Map.set(i, scope.functions->Array.map(f => signature(scope, `${i}.`, f)))
  )
  let items = items =>
    items->Array.flatMap((item: Syntax.item) =>
      switch item {
      | Interface(n) =>
        switch functions->Map.get(n.name) {
        | Some(functions) => functions
        | None =>
          refuse(Undefined(n.name), n.place)
          []
        }
      | Function(n, f) => [signature(world.scope, "", (n, f))]
      | Outside => []
      }
    )
  let imports = items(world.imports)
  let exports = items(world.exports)
  {
    package: file.package,
    name: world.name.name,
    imports: imports->Array.filterMap(f => f),
    exports: exports->Array.filterMap(f => f),
  }
}

let read = text => {
  let (parsed, refusals) = Syntax.parse(text)
  let world = switch parsed {
  | Some({world: Some(world)} as file) => Some(resolve(file, world, refusals))
  | Some({world: None}) | None => None
  }
  switch (world, refusals) {
  | (Some(world), []) => Ok(world)
  | (Some(_) | None, refusals) =>
    Error(
      refusals->Array.toSorted((a, b) =>
        a.line == b.line ? Int.compare(a.column, b.column) : Int.compare(a.line, b.line)
      ),
    )
  }
}

let package = world => world.package
let name = world => world.name
let imports = world => world.imports
let exports = world => world.exports

type step =
  | Parameter(int)
  | Returned
  | Field(string)
  | Case(string)
  | Element
  | Item(int)
  | Present
  | Success
  | Failure

type mismatch =
  | Undeclared(string)
  | Missing(string)
  | Count({call: string, caller: int, export: int})
  | Mistyped({call: string, at: array<step>})
  | Unheld({call: string, at: array<step>, case: string})

/** Which way a value goes, a parameter to the export and a result back to the caller. */
type flow = Given | Back

/**
 * Two types compared, a parameter's exactly, a result's holding where every case or flag the
 * export names is one the caller holds, kd7f9.
 */
let rec compare = (found, ~call, ~flow, at, caller, export) => {
  let mistyped = at => found->Array.push(Mistyped({call, at}))
  let into = (at, step) => at->Array.concat([step])
  let payloads = (at, caller, export) =>
    switch (caller, export) {
    | (Some(a), Some(b)) => compare(found, ~call, ~flow, at, a, b)
    | (None, None) => ()
    | (Some(_), None) | (None, Some(_)) => mistyped(at)
    }
  // The names of either side compared, each shared one handed to `both`.
  let named = (callers: array<string>, exports: array<string>, both) => {
    callers->Array.forEach(n =>
      if exports->Array.includes(n) {
        both(n)
      } else {
        switch flow {
        | Given => mistyped(into(at, Case(n)))
        | Back => ()
        }
      }
    )
    exports->Array.forEach(n =>
      if !(callers->Array.includes(n)) {
        switch flow {
        | Given => mistyped(into(at, Case(n)))
        | Back => found->Array.push(Unheld({call, at, case: n}))
        }
      }
    )
  }
  switch (caller, export) {
  | (Primitive(a), Primitive(b)) =>
    if a != b {
      mistyped(at)
    }
  | (List(a), List(b)) => compare(found, ~call, ~flow, into(at, Element), a, b)
  | (Option(a), Option(b)) => compare(found, ~call, ~flow, into(at, Present), a, b)
  | (Tuple(a), Tuple(b)) =>
    if a->Array.length != b->Array.length {
      mistyped(at)
    } else {
      a->Array.forEachWithIndex((t, i) =>
        b->Array.get(i)->Option.forEach(u => compare(found, ~call, ~flow, into(at, Item(i)), t, u))
      )
    }
  | (Result(a), Result(b)) =>
    payloads(into(at, Success), a.success, b.success)
    payloads(into(at, Failure), a.failure, b.failure)
  | (Record(a), Record(b)) =>
    let field = (fields: array<field>, n) => fields->Array.find(f => f.name == n)
    let names = (fields: array<field>) => fields->Array.map(f => f.name)
    names(a.fields)->Array.forEach(n =>
      switch (field(a.fields, n), field(b.fields, n)) {
      | (Some(f), Some(g)) => compare(found, ~call, ~flow, into(at, Field(n)), f.type_, g.type_)
      | (Some(_) | None, None) | (None, Some(_)) => mistyped(into(at, Field(n)))
      }
    )
    names(b.fields)->Array.forEach(n =>
      if field(a.fields, n) == None {
        mistyped(into(at, Field(n)))
      }
    )
  | (Variant(a), Variant(b)) =>
    let payload = (cases: array<case>, n) =>
      cases->Array.find(c => c.label == n)->Option.flatMap(c => c.payload)
    let names = (cases: array<case>) => cases->Array.map(c => c.label)
    named(names(a.cases), names(b.cases), n =>
      payloads(into(at, Case(n)), payload(a.cases, n), payload(b.cases, n))
    )
  | (Enum(a), Enum(b)) => named(a.cases, b.cases, _ => ())
  | (Flags(a), Flags(b)) => named(a.flags, b.flags, _ => ())
  | (
      Primitive(_)
      | List(_)
      | Option(_)
      | Tuple(_)
      | Result(_)
      | Record(_)
      | Variant(_)
      | Enum(_)
      | Flags(_),
      Primitive(_)
      | List(_)
      | Option(_)
      | Tuple(_)
      | Result(_)
      | Record(_)
      | Variant(_)
      | Enum(_)
      | Flags(_),
    ) =>
    mistyped(at)
  }
}

let matches = (caller, ~calls, ~exports) => {
  let found = []
  calls->Array.forEach(call => {
    let mine = caller.imports->Array.find(f => f.name == call)
    let theirs = exports->Array.find((f: function) => f.name == call)
    if mine == None {
      found->Array.push(Undeclared(call))
    }
    if theirs == None {
      found->Array.push(Missing(call))
    }
    switch (mine, theirs) {
    | (Some(a), Some(b)) =>
      let (counted, given) = (a.parameters->Array.length, b.parameters->Array.length)
      if counted != given {
        found->Array.push(Count({call, caller: counted, export: given}))
      } else {
        a.parameters->Array.forEachWithIndex((p, i) =>
          b.parameters
          ->Array.get(i)
          ->Option.forEach(
            q => compare(found, ~call, ~flow=Given, [Parameter(i)], p.type_, q.type_),
          )
        )
      }
      switch (a.result, b.result) {
      | (Some(t), Some(u)) => compare(found, ~call, ~flow=Back, [Returned], t, u)
      | (None, None) => ()
      | (Some(_), None) | (None, Some(_)) => found->Array.push(Mistyped({call, at: [Returned]}))
      }
    | (Some(_) | None, None) | (None, Some(_)) => ()
    }
  })
  found->Array.length == 0 ? Ok() : Error(found)
}
