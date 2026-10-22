/***
 * A file of WIT lexed and parsed, RFC kd7f9's subset, each construct it refuses read through and
 * kept so every one is found. A token out of place stops the reading there.
 */

open Lexer
open! Reader

type definition =
  | Alias(ty)
  | RecordOf(array<(named, ty)>)
  | VariantOf(array<(named, option<ty>)>)
  | EnumOf(array<named>)
  | FlagsOf(array<named>)
  | Opaque

/** What a name in a scope stands for, a type of its own, one used from an interface, or neither. */
type entry =
  | Defines(definition)
  | Uses({interface: named, original: string})
  | Elsewhere

type signature = {parameters: array<(named, ty)>, result: option<ty>}

/** An interface's items or a world's, `used` the interfaces its uses name. */
type scope = {
  id: string,
  types: Map.t<string, (entry, place)>,
  functions: array<(named, signature)>,
  used: array<named>,
}

type item =
  | Interface(named)
  | Function(named, signature)
  | Outside

type world = {name: named, scope: scope, imports: array<item>, exports: array<item>}

type package = {namespace: string, name: string, version: option<string>}

type file = {package: option<package>, interfaces: Map.t<string, scope>, world: option<world>}

let scopeOf = id => {id, types: Map.make(), functions: [], used: []}

let define = (s, scope, n: named, entry) =>
  if scope.types->Map.has(n.name) {
    refuse(s, Repeated(n.name), n.place)
  } else {
    scope.types->Map.set(n.name, (entry, n.place))
  }

let signature = s => {
  if isWord(s, "async") {
    refuse(s, Refused(Beyond("async")), peek(s, 0).place)
    advance(s)
  }
  if !isWord(s, "func") {
    unexpected(s, "`func`")
  }
  advance(s)
  expect(s, "(")
  let parameters = sequence(
    s,
    ")",
    () => {
      let n = name(s)
      expect(s, ":")
      (n, ty(s))
    },
    ~expected="a parameter",
  )
  unique(s, parameters->Array.map(((n, _)) => n))
  let result = if isMark(s, "->") {
    advance(s)
    Some(ty(s))
  } else {
    None
  }
  {parameters, result}
}

/** A `use` of an interface's types into a scope, one of another package's refused. */
let use = (s, scope) => {
  let place = peek(s, 0).place
  advance(s)
  let from = path(s)
  switch from {
  | Ok(interface) => scope.used->Array.push(interface)
  | Error(foreign) => refuse(s, Refused(Foreign(foreign)), place)
  }
  expect(s, ".")
  expect(s, "{")
  let names = sequence(
    s,
    "}",
    () => {
      let original = name(s)
      if isWord(s, "as") {
        advance(s)
        (original, name(s))
      } else {
        (original, original)
      }
    },
    ~least=1,
    ~expected="a name",
  )
  expect(s, ";")
  names->Array.forEach(((original, local)) =>
    define(
      s,
      scope,
      local,
      switch from {
      | Ok(interface) => Uses({interface, original: original.name})
      | Error(_) => Elsewhere
      },
    )
  )
}

/** A type's definition, whether the next item is one, read into its scope. */
let typedef = (s, scope) => {
  let place = peek(s, 0).place
  let cases = () => {
    let n = name(s)
    expect(s, "{")
    let cases = sequence(s, "}", () => name(s), ~least=1, ~expected="a name")
    unique(s, cases)
    (n, cases)
  }
  switch peek(s, 0).token {
  | Word("type") =>
    advance(s)
    let n = name(s)
    expect(s, "=")
    let t = ty(s)
    expect(s, ";")
    define(s, scope, n, Defines(Alias(t)))
    true
  | Word("record") =>
    advance(s)
    let n = name(s)
    expect(s, "{")
    let fields = sequence(
      s,
      "}",
      () => {
        let f = name(s)
        expect(s, ":")
        (f, ty(s))
      },
      ~least=1,
      ~expected="a field",
    )
    unique(s, fields->Array.map(((f, _)) => f))
    define(s, scope, n, Defines(RecordOf(fields)))
    true
  | Word("variant") =>
    advance(s)
    let n = name(s)
    expect(s, "{")
    let cases = sequence(
      s,
      "}",
      () => {
        let c = name(s)
        if isMark(s, "(") {
          advance(s)
          let payload = ty(s)
          expect(s, ")")
          (c, Some(payload))
        } else {
          (c, None)
        }
      },
      ~least=1,
      ~expected="a case",
    )
    unique(s, cases->Array.map(((c, _)) => c))
    define(s, scope, n, Defines(VariantOf(cases)))
    true
  | Word("enum") =>
    advance(s)
    let (n, cases) = cases()
    define(s, scope, n, Defines(EnumOf(cases)))
    true
  | Word("flags") =>
    advance(s)
    let (n, flags) = cases()
    // The component model's binary holds 32 flags at most, as wasmparser's validator refuses.
    flags
    ->Array.get(32)
    ->Option.forEach(f => refuse(s, Refused(Beyond("flags past 32")), f.place))
    define(s, scope, n, Defines(FlagsOf(flags)))
    true
  | Word("resource") =>
    advance(s)
    let n = name(s)
    refuse(s, Refused(Resource), place)
    isMark(s, "{") ? skip(s, "{", "}") : expect(s, ";")
    define(s, scope, n, Defines(Opaque))
    true
  | Word(_) | Escaped(_) | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End => false
  }
}

let interface = (s, scope) => {
  expect(s, "{")
  while !isMark(s, "}") {
    gates(s)
    if isWord(s, "use") {
      use(s, scope)
    } else if !typedef(s, scope) {
      let n = name(s, ~expected="an item or `}`")
      expect(s, ":")
      let f = signature(s)
      expect(s, ";")
      if scope.functions->Array.some(((m, _)) => m.name == n.name) {
        refuse(s, Repeated(n.name), n.place)
      } else {
        scope.functions->Array.push((n, f))
      }
    }
  }
  advance(s)
  // An interface is one namespace, so a function holding a type's name is refused, as WIT.md says.
  scope.functions->Array.forEach(((n, _)) =>
    if scope.types->Map.has(n.name) {
      refuse(s, Repeated(n.name), n.place)
    }
  )
}

/** An import or an export of a world, an interface of this file or a function of its own. */
let external_ = (s, items) => {
  let place = peek(s, 0).place
  advance(s)
  let start = s.at
  let first = name(s)
  let foreign = () => {
    switch path(s) {
    | Error(foreign) => refuse(s, Refused(Foreign(foreign)), place)
    | Ok(_) => refuse(s, Refused(Beyond("named interface")), place)
    }
    expect(s, ";")
    Outside
  }
  let item = if isMark(s, ";") {
    advance(s)
    Interface(first)
  } else if isMark(s, ":") {
    let after = peek(s, 1).token
    if after == Word("func") || after == Word("async") {
      advance(s)
      let f = signature(s)
      expect(s, ";")
      Function(first, f)
    } else if after == Word("interface") {
      refuse(s, Refused(Beyond("inline interface")), place)
      advance(s)
      advance(s)
      skip(s, "{", "}")
      Outside
    } else if peek(s, 2).token == Mark("/") {
      // An unnamed path, `{namespace}:{package}/{interface}`, is read again from its start.
      s.at = start
      foreign()
    } else {
      advance(s)
      foreign()
    }
  } else {
    unexpected(s, "`;` or `:`")
  }
  let key = switch item {
  | Interface(n) | Function(n, _) => Some(n)
  | Outside => None
  }
  key->Option.forEach(n =>
    if (
      items->Array.some(i =>
        switch i {
        | Interface(m) | Function(m, _) => m.name == n.name
        | Outside => false
        }
      )
    ) {
      refuse(s, Repeated(n.name), n.place)
    }
  )
  items->Array.push(item)
}

let world = (s, n) => {
  let w = {name: n, scope: scopeOf("world"), imports: [], exports: []}
  expect(s, "{")
  while !isMark(s, "}") {
    gates(s)
    let place = peek(s, 0).place
    switch peek(s, 0).token {
    | Word("import") => external_(s, w.imports)
    | Word("export") => external_(s, w.exports)
    | Word("use") => use(s, w.scope)
    | Word("include") =>
      advance(s)
      path(s)->ignore
      refuse(s, Refused(Include), place)
      if isWord(s, "with") {
        advance(s)
        skip(s, "{", "}")
      } else {
        expect(s, ";")
      }
    | Word("resource") => typedef(s, w.scope)->ignore
    | Word("type" | "record" | "variant" | "enum" | "flags") =>
      refuse(s, Refused(Beyond("type in a world")), place)
      typedef(s, w.scope)->ignore
    | Word(_) | Escaped(_) | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End =>
      unexpected(s, "`import`, `export`, `use`, `include` or `}`")
    }
  }
  advance(s)
  // A name a world uses is one of its imports, so an imported function holding it is refused.
  w.imports->Array.forEach(item =>
    switch item {
    | Function(n, _) if w.scope.types->Map.has(n.name) => refuse(s, Repeated(n.name), n.place)
    | Function(_) | Interface(_) | Outside => ()
    }
  )
  w
}

/** The package line, its name refused past `{namespace}:{name}` and its block where it has one. */
let packageLine = s => {
  let place = peek(s, 0).place
  advance(s)
  let namespace = name(s)
  expect(s, ":")
  let package = name(s)
  if isMark(s, ":") || isMark(s, "/") {
    refuse(s, Refused(Beyond("nested package name")), place)
    while isMark(s, ":") || isMark(s, "/") {
      advance(s)
      name(s)->ignore
    }
  }
  let version = isMark(s, "@") ? Some(version(s)) : None
  if isMark(s, "{") {
    refuse(s, Refused(Beyond("nested package")), place)
    skip(s, "{", "}")
    None
  } else {
    expect(s, ";")
    Some({namespace: namespace.name, name: package.name, version})
  }
}

/** A file parsed, none where a token out of place stopped it, with every refusal found. */
let parse = text => {
  let refusals = []
  let tokens = lex(text, (problem, place: place) =>
    refusals->Array.push({problem, line: place.line, column: place.column})
  )
  let s = {tokens, at: 0, refusals}
  let interfaces = Map.make()
  let names = []
  let named = (n: named) =>
    if names->Array.includes(n.name) {
      refuse(s, Repeated(n.name), n.place)
      false
    } else {
      names->Array.push(n.name)
      true
    }
  let parsed = try {
    let package = isWord(s, "package") ? packageLine(s) : None
    let only = ref(None)
    while peek(s, 0).token != End {
      gates(s)
      let place = peek(s, 0).place
      switch peek(s, 0).token {
      | Word("interface") =>
        advance(s)
        let n = name(s)
        let scope = scopeOf(`interface ${n.name}`)
        interface(s, scope)
        if named(n) {
          interfaces->Map.set(n.name, scope)
        }
      | Word("world") =>
        advance(s)
        let n = name(s)
        let w = world(s, n)
        switch only.contents {
        | Some(_) => refuse(s, SecondWorld, n.place)
        | None => only := (named(n) ? Some(w) : None)
        }
      | Word("use") =>
        advance(s)
        let from = path(s)
        if isWord(s, "as") {
          advance(s)
          name(s)->ignore
        }
        expect(s, ";")
        switch from {
        | Error(foreign) => refuse(s, Refused(Foreign(foreign)), place)
        | Ok(_) => refuse(s, Refused(Beyond("top-level use")), place)
        }
      | Word("package") =>
        let start = s.at
        if packageLine(s) != None {
          s.at = start
          unexpected(s, "`interface`, `world` or `use`")
        }
      | Word(_) | Escaped(_) | Mark(_) | Number(_) | Version(_) | Text(_) | Bad(_) | End =>
        unexpected(s, "`interface`, `world` or `use`")
      }
    }
    if only.contents == None {
      refuse(s, NoWorld, peek(s, 0).place)
    }
    Some({package, interfaces, world: only.contents})
  } catch {
  | Stop => None
  }
  (parsed, refusals)
}
