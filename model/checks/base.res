/**
 * What every check stands on: the bindings, the graph read as the checks read it, and how a
 * dimension prints.
 */
type url
@new external url: (string, string) => url = "URL"
@new external urlIn: (string, url) => url = "URL"
@new external absolute: string => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:fs") external readdirSync: url => array<string> = "readdirSync"
@module("node:fs") external readFileSync: (url, @as("utf8") _) => string = "readFileSync"
@module("node:fs") external existsSync: url => bool = "existsSync"
@module("node:fs") external writeFileSync: (url, string) => unit = "writeFileSync"
type process
@val external process: process = "process"
@get external argv: process => array<string> = "argv"
@set external setExitCode: (process, int) => unit = "exitCode"
@val external number: string => float = "Number"
@val @scope("Number") external isInteger: float => bool = "isInteger"

let args = process->argv
let components = Components.components
let component = n => components->Dict.get(n)
let edgesOf = n => component(n)->Option.mapOr([], p => p.edges)
let boundary = n => Boundaries.boundaries->Dict.get(n)
let num = Float.toString
let int = Int.toString
let byText = (a: string, b: string) => a < b ? -1. : a > b ? 1. : 0.

let layerName = layer =>
  layer == Components.vendor ? "ground" : layer > 0 ? `+${int(layer)}` : int(layer)
let known = to_ => !(to_->String.startsWith("?"))
let tag = (edge: Components.edge) => `${(edge.when_ :> string)}/${edge.hard ? "hard" : "soft"}`
let designed = components->Dict.toArray->Array.filter(((_, p)) => p.kind == None)
let line = (from, edge: Components.edge) => `${from} -> ${edge.to_} ${tag(edge)}: ${edge.why}`
let contracted = to_ => boundary(to_)->Option.flatMap(b => b.contract)->Option.isSome
let isGround = n => component(n)->Option.flatMap(p => p.kind) == Some(#ground)

/** Every cycle `next` closes among `names`, by a depth-first walk that remembers its path. */
let cycles = (next: string => array<string>, names: array<string>): array<string> => {
  let found = []
  let state: Map.t<string, [#on | #done]> = Map.make()
  let rec walk = (name, path) =>
    switch state->Map.get(name) {
    | Some(#done) => ()
    | Some(#on) =>
      found->Array.push(
        path
        ->Array.slice(~start=path->Array.indexOf(name))
        ->Array.concat([name])
        ->Array.join(" -> "),
      )
    | None =>
      state->Map.set(name, #on)
      next(name)->Array.forEach(n => walk(n, path->Array.concat([name])))
      state->Map.set(name, #done)
    }
  names->Array.forEach(name => walk(name, []))
  found
}

let layerOf = n => component(n)->Option.mapOr(0, p => p.layer)

/** The order the edges `when_` selects allow, the ground first. */
let order = (when_: Components.edge => bool): array<string> => {
  let out = []
  let seen = Set.make()
  let rec visit = n =>
    if !(seen->Set.has(n)) {
      seen->Set.add(n)
      edgesOf(n)->Array.forEach(x =>
        if when_(x) && known(x.to_) {
          visit(x.to_)
        }
      )
      out->Array.push(n)
    }
  components
  ->Dict.keysToArray
  // By layer, then by name, so the order is the graph's and not where each part was declared.
  ->Array.toSorted((a, b) =>
    layerOf(a) == layerOf(b) ? byText(a, b) : Int.toFloat(layerOf(a) - layerOf(b))
  )
  ->Array.forEach(visit)
  out
}

type split = {violations: array<string>, assumed: array<string>}

/** The edges `when_` selects that end at a boundary, split by whether its contract is written. */
let atBoundaries = (when_: Components.edge => bool): split => {
  let hits =
    designed->Array.flatMap(((n, p)) =>
      p.edges->Array.filter(x => when_(x) && !known(x.to_))->Array.map(x => (n, x))
    )
  {
    violations: hits
    ->Array.filter(((_, x)) => !contracted(x.to_))
    ->Array.map(((n, x)) => `no contract: ${line(n, x)}`),
    assumed: hits
    ->Array.filter(((_, x)) => contracted(x.to_))
    ->Array.map(((n, x)) =>
      `${n} assumes ${x.to_}: ${boundary(x.to_)->Option.flatMap(b => b.contract)->Option.getOr("")}`
    ),
  }
}

let failed = ref(false)

/** What a block in work fails, `model/plan/work.res`: listed in red after every dimension, failing
 * nothing. */
let inWork: array<string> = []

@val @scope(("process", "env")) external noColor: Nullable.t<string> = "NO_COLOR"
let red = text => noColor->Nullable.toOption != None ? text : `\u001b[31m${text}\u001b[0m`

let shownInWork = () =>
  if inWork->Array.length > 0 {
    Console.log(
      red(
        `\n# In work, failing nothing until accepted\n${inWork
          ->Array.map(l => `  ! ${l}`)
          ->Array.join("\n")}`,
      ),
    )
  }
let dimension = (title, question, violations, ~notes=[], ~assumed=[], ()) => {
  Console.log(`\n# ${title}\n${question}`)
  Console.log(
    violations->Array.length > 0
      ? violations->Array.map(v => `  x ${v}`)->Array.join("\n")
      : "  no violation",
  )
  assumed->Array.forEach(a => Console.log(`  ~ ${a}`))
  notes->Array.forEach(n => Console.log(`  ${n}`))
  if violations->Array.length > 0 {
    failed := true
  }
}

/**
 * A value of JSON read as one kind, or none: a match on JSON's own cases leaves a wildcard over them,
 * which warning 4 refuses, so every read goes through one of these.
 */
let text = (j: option<JSON.t>) => j->Option.flatMap(JSON.Decode.string)
let numeric = (j: option<JSON.t>) => j->Option.flatMap(JSON.Decode.float)
let object = (j: option<JSON.t>) => j->Option.flatMap(JSON.Decode.object)
let list = (j: option<JSON.t>) => j->Option.flatMap(JSON.Decode.array)
let truth = (j: option<JSON.t>) => j->Option.flatMap(JSON.Decode.bool)

/** A member of an object, or none where the value is no object. */
let member = (j: JSON.t, k) => j->JSON.Decode.object->Option.flatMap(d => d->Dict.get(k))

let orNone = (xs, sep) => xs->Array.length > 0 ? xs->Array.join(sep) : "none"
let serve = (x: Components.edge) => x.when_ == #serve
let ons = (d: Steps.deployment, f) => d.on->Array.includes(f)

/** The repository's root, which every path a check reads is taken from. */
let root = url("../../", importMetaUrl)

type dirent
type listing = {withFileTypes: bool}
@module("node:fs") external entries: (url, listing) => array<dirent> = "readdirSync"
@get external entryName: dirent => string = "name"
@send external isDirectory: dirent => bool = "isDirectory"
