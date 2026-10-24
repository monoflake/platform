/**
 * The as-built graph, each block in the place of every name it provides, RFC s42ex. A merged
 * node keeps its main name's own attributes and answers what each name it provides answers, and
 * each boundary name it provides.
 */
open Base

/** The name of the node standing for the platform beneath, `Provided.beneath`, RFC 94y0d. */
let beneath = "beneath"

/** The manifest a block's directory holds for each of its languages once its code is written. */
let manifest = (l: Blocks.lang) =>
  switch l {
  | #rescript => "package.json"
  | #rust => "Cargo.toml"
  | #nix => "flake.nix"
  | #docker => "Dockerfile"
  }

/**
 * Every block named for a component, by its main name: this repository's with its code written,
 * `Blocks.expected`, and each a sibling declares, which its own check refuses unless accepted.
 */
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
  ->Array.concat(
    Provided.elsewhere->Dict.keysToArray->Array.filter(n => component(n)->Option.isSome),
  )
  ->Array.toSorted(byText)
}

let declaredOf = main => Provided.all->Dict.get(main)

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

/** A design edge of `from` as block `main` builds it, the contract it carries declared, s42ex. */
let carry = (main, from, edge: Components.edge) =>
  switch declaredOf(main)
  ->Option.flatMap(b => b.carries)
  ->Option.getOr([])
  ->Array.find((c: Provided.carried) => c.from == from && c.to_ == edge.to_) {
  | Some(c) => {...edge, contract: c.contract}
  | None => edge
  }

/**
 * An edge from a node providing `own`, to every node its target is, none where it is internal. It
 * carries `?x` as the contract of an edge to a boundary it points at the provider of.
 */
let retarget = (own: array<string>, edge: Components.edge) =>
  if edge.beneath == Some(true) {
    [{...edge, to_: beneath}]
  } else if own->Array.includes(edge.to_) {
    []
  } else {
    let carried = edge.to_->String.startsWith("?") && edge.contract->Option.getOr([]) == []
    realize(edge.to_)->Array.map(t =>
      carried && t != edge.to_ ? {...edge, to_: t, contract: [edge.to_]} : {...edge, to_: t}
    )
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

/**
 * The as-built graph of the design's `nodes`, a block merged from every name it provides. A name no
 * block provides keeps its node and none of its edges.
 */
let derive = (nodes: dict<Components.component>): dict<Components.component> => {
  let merged = mains->Array.filterMap(m =>
    nodes
    ->Dict.get(m)
    ->Option.map((main: Components.component) => {
      let names = provides(m)
      let edges =
        names
        ->Array.flatMap(
          n => nodes->Dict.get(n)->Option.mapOr([], c => c.edges->Array.map(e => carry(m, n, e))),
        )
        ->Array.concat(declaredOf(m)->Option.mapOr([], b => b.extra))
        ->Array.flatMap(e => retarget(names, e))
      let answers = union(
        names
        ->Array.map(n => nodes->Dict.get(n)->Option.flatMap(c => c.answers)->Option.getOr([]))
        ->Array.concat([names->Array.filter(n => n->String.startsWith("?"))]),
      )
      (m, {...main, edges, answers: ?(answers == [] ? None : Some(answers))})
    })
  )
  let standing =
    nodes
    ->Dict.toArray
    ->Array.filter(((n, _)) => providers(n) == [])
    ->Array.map(((n, c)) => (n, {...c, edges: []}))
  Array.concatMany(merged, [standing, [(beneath, Provided.beneath)]])
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
