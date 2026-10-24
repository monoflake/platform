/**
 * The as-built graph, each block in the place of every name it provides, RFC s42ex. A merged
 * node keeps its main name's own attributes and answers what each name it provides answers.
 */
open Base

/** The node standing for the platform beneath, to the one above a vendor, RFC 94y0d. */
let beneath = "beneath"

/** The manifest a block's directory holds for each of its languages once its code is written. */
let manifest = (l: Blocks.lang) =>
  switch l {
  | #rescript => "package.json"
  | #rust => "Cargo.toml"
  | #nix => "flake.nix"
  | #docker => "Dockerfile"
  }

/** Every block named for a component with its code written, by its main name, `Blocks.expected`. */
let mains = {
  let (expected, _, _) = Blocks.expected()
  expected
  ->Map.entries
  ->Array.fromIterator
  ->Array.filter(((path, h)) =>
    component(h.name)->Option.isSome &&
      h.languages->Array.every(l => existsSync(urlIn(`${path}/${manifest(l)}`, root)))
  )
  ->Array.map(((_, h)) => h.name)
  ->Array.toSorted(byText)
}

let declaredOf = main => Provided.blocks->Dict.get(main)

/** The names a block provides, its main name first. */
let provides = main => [main]->Array.concat(declaredOf(main)->Option.mapOr([], b => b.provides))

/** The blocks providing a name, by their main names. */
let providers = name => mains->Array.filter(m => provides(m)->Array.includes(name))

/** A name as the as-built graph knows it, each block providing it, or the name itself. */
let realize = name =>
  switch providers(name) {
  | [] => [name]
  | by => by
  }

/** An edge from a node providing `own`, to every node its target is, none where it is internal. */
let retarget = (own: array<string>, edge: Components.edge) =>
  if edge.beneath == Some(true) {
    [{...edge, to_: beneath}]
  } else if own->Array.includes(edge.to_) {
    []
  } else {
    realize(edge.to_)->Array.map(t => {...edge, to_: t})
  }

let union = (lists: array<array<string>>) => {
  let out = []
  lists->Array.forEach(l =>
    l->Array.forEach(x =>
      if !(out->Array.includes(x)) {
        out->Array.push(x)
      }
    )
  )
  out
}

/** The as-built graph of the design's `nodes`, a block merged from every name it provides. */
let derive = (nodes: dict<Components.component>): dict<Components.component> => {
  let merged = mains->Array.filterMap(m =>
    nodes
    ->Dict.get(m)
    ->Option.map((main: Components.component) => {
      let names = provides(m)
      let edges =
        names
        ->Array.flatMap(n => nodes->Dict.get(n)->Option.mapOr([], c => c.edges))
        ->Array.concat(declaredOf(m)->Option.mapOr([], b => b.extra))
        ->Array.flatMap(e => retarget(names, e))
      let answers = union(
        names->Array.map(n => nodes->Dict.get(n)->Option.flatMap(c => c.answers)->Option.getOr([])),
      )
      (m, {...main, edges, answers: ?(answers == [] ? None : Some(answers))})
    })
  )
  let standing =
    nodes
    ->Dict.toArray
    ->Array.filter(((n, _)) => providers(n) == [])
    ->Array.map(((n, c)) => (n, {...c, edges: c.edges->Array.flatMap(e => retarget([], e))}))
  let platformBeneath: Components.component = {
    layer: Components.vendor,
    kind: #ground,
    edges: [],
    uses: [],
  }
  Array.concatMany(merged, [standing, [(beneath, platformBeneath)]])
  ->Array.toSorted(((a, _), (b, _)) => byText(a, b))
  ->Dict.fromArray
}

/** The as-built graph, its records written by the blocks providing each writer. */
let graph = {
  let nodes = derive(components)
  {
    components: nodes,
    own: derive(Components.own),
    fillers: role =>
      design.fillers(role)->Array.concat(
        providers(role)->Array.filterMap(m => nodes->Dict.get(m)->Option.map(c => (m, c))),
      ),
    records: Records.records->Array.map(r => {
      ...r,
      writes: union(r.writes->Array.map(realize)),
    }),
  }
}
