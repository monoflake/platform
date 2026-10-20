/** What every check stands on: the bindings, the graph read as the checks read it, and how a dimension prints. */
type url
@new external url: (string, string) => url = "URL"
@new external urlIn: (string, url) => url = "URL"
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
let parts = Parts.parts
let part = n => parts->Dict.get(n)
let edgesOf = n => part(n)->Option.mapOr([], p => p.edges)
let boundary = n => Boundaries.boundaries->Dict.get(n)
let num = Float.toString
let int = Int.toString
let byText = (a: string, b: string) => a < b ? -1. : a > b ? 1. : 0.

let layerName = layer =>
  layer == Parts.vendor ? "ground" : layer > 0 ? `+${int(layer)}` : int(layer)
let known = to_ => !(to_->String.startsWith("?"))
let tag = (edge: Parts.edge) => `${(edge.when_ :> string)}/${edge.hard ? "hard" : "soft"}`
let designed = parts->Dict.toArray->Array.filter(((_, p)) => p.kind == None)
let line = (from, edge: Parts.edge) => `${from} -> ${edge.to_} ${tag(edge)}: ${edge.why}`
let contracted = to_ => boundary(to_)->Option.flatMap(b => b.contract)->Option.isSome
let isGround = n => part(n)->Option.flatMap(p => p.kind) == Some(#ground)

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

let layerOf = n => part(n)->Option.mapOr(0, p => p.layer)

/** The order the edges `when_` selects allow, the ground first. */
let order = (when_: Parts.edge => bool): array<string> => {
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
  parts
  ->Dict.keysToArray
  ->Array.toSorted((a, b) => Int.toFloat(layerOf(a) - layerOf(b)))
  ->Array.forEach(visit)
  out
}

type split = {violations: array<string>, assumed: array<string>}

/** The edges `when_` selects that end at a boundary, split by whether its contract is written. */
let atBoundaries = (when_: Parts.edge => bool): split => {
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

let orNone = (xs, sep) => xs->Array.length > 0 ? xs->Array.join(sep) : "none"
let serve = (x: Parts.edge) => x.when_ == #serve
let ons = (d: Steps.deployment, f) => d.on->Array.includes(f)

/** The repository's root, which every path a check reads is taken from. */
let root = url("../../", importMetaUrl)

type dirent
type listing = {withFileTypes: bool}
@module("node:fs") external entries: (url, listing) => array<dirent> = "readdirSync"
@get external entryName: dirent => string = "name"
@send external isDirectory: dirent => bool = "isDirectory"

let steps = Steps.steps
