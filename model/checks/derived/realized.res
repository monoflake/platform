/**
 * The as-built graph, each block in the place of every name it provides, RFC s42ex. A merged
 * node keeps its main name's own attributes save a role's kind, and answers what each name it
 * provides answers, and each boundary name it provides.
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

/** The blocks one graph is derived from, by their main names, and what each declares. */
type running = {mains: array<string>, declared: dict<Provided.block>}

/** Every block with its code, the as-built graph's when no deployment is named. */
let built = {mains, declared: Provided.all}

let declaredOf = (r: running, main) => r.declared->Dict.get(main)

/** The names a block provides, its main name first. */
let provides = (r, main) =>
  [main]->Array.concat(declaredOf(r, main)->Option.mapOr([], b => b.provides))

/** The blocks providing a name, by their main names. */
let providers = (r: running, name) =>
  r.mains->Array.filter(m => provides(r, m)->Array.includes(name))

/** A name as the as-built graph knows it, each block providing it, or the name itself. */
let realize = (r, name) =>
  switch providers(r, name) {
  | [] => [name]
  | by => by
  }

/** A design edge of `from` as block `main` builds it, the contract it carries declared, s42ex. */
let carry = (r, main, from, edge: Components.edge) =>
  switch declaredOf(r, main)
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
let retarget = (r, own: array<string>, edge: Components.edge) =>
  if edge.beneath == Some(true) {
    [{...edge, to_: beneath}]
  } else if own->Array.includes(edge.to_) {
    []
  } else {
    let carried = edge.to_->String.startsWith("?") && edge.contract->Option.getOr([]) == []
    realize(r, edge.to_)->Array.map(t =>
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
 * The as-built graph of the design's `nodes` with the blocks `r` running, a block merged from every
 * name it provides. A name no block provides keeps its node and none of its edges.
 */
let derive = (r: running, nodes: dict<Components.component>): dict<Components.component> => {
  let merged = r.mains->Array.filterMap(m =>
    nodes
    ->Dict.get(m)
    ->Option.map((main: Components.component) => {
      let names = provides(r, m)
      let edges =
        names
        ->Array.flatMap(
          n =>
            nodes->Dict.get(n)->Option.mapOr([], c => c.edges->Array.map(e => carry(r, m, n, e))),
        )
        ->Array.concat(declaredOf(r, m)->Option.mapOr([], b => b.extra))
        ->Array.flatMap(e => retarget(r, names, e))
      let answers = union(
        names
        ->Array.map(n => nodes->Dict.get(n)->Option.flatMap(c => c.answers)->Option.getOr([]))
        ->Array.concat([names->Array.filter(n => n->String.startsWith("?"))]),
      )
      // A block named for a role is code that runs, so the rules hold it as they hold a component.
      let kind = main.kind == Some(#provided) ? None : main.kind
      (m, {...main, ?kind, edges, answers: ?(answers == [] ? None : Some(answers))})
    })
  )
  let standing =
    nodes
    ->Dict.toArray
    ->Array.filter(((n, _)) => providers(r, n) == [])
    ->Array.map(((n, c)) => (n, {...c, edges: []}))
  Array.concatMany(merged, [standing, [(beneath, Provided.beneath)]])
  ->Array.toSorted(((a, _), (b, _)) => byText(a, b))
  ->Dict.fromArray
}

/** The as-built graph of the blocks `r` running, its records written by each writer's providers. */
let graphOf = (r: running) => {
  let nodes = derive(r, components)
  {
    components: nodes,
    own: derive(r, Components.own),
    // A block named for a driver role is the drivers given filling it, RFC 7ykg6, no component.
    fillers: role =>
      design.fillers(role)->Array.concat(
        providers(r, role)
        ->Array.filter(m => m != role || Drivers.asked->Dict.get(role)->Option.isNone)
        ->Array.filterMap(m => nodes->Dict.get(m)->Option.map(c => (m, c))),
      ),
    records: Records.records->Array.map(held => {
      ...held,
      writes: union(held.writes->Array.map(n => realize(r, n))),
    }),
  }
}

/** The as-built graph of every block with its code. */
let graph = graphOf(built)

/** The main names of the blocks a deployment's names are filled by, RFC vgvx6. */
let blocksIn = (d: Provided.deployed) =>
  union([
    d.fills->Array.filterMap(((_, f)) =>
      switch f {
      | Block(main) => Some(main)
      | Vendor(_) | Workload(_) => None
      }
    ),
  ])->Array.toSorted(byText)

/** The blocks running in a deployment, those its names are filled by whose code is written. */
let runningIn = (d: Provided.deployed) => {
  mains: blocksIn(d)->Array.filter(m => mains->Array.includes(m)),
  declared: Provided.all,
}

/** The names a deployment fills by a vendor's resource or a workload, each with what fills it. */
let filledApart = (d: Provided.deployed) =>
  d.fills->Array.filterMap(((name, f)) =>
    switch f {
    | Block(_) => None
    | Vendor({vendor, resource}) => Some((name, `${resource}, a resource of ${vendor}`))
    | Workload(what) => Some((name, `${what}, a workload`))
    }
  )
