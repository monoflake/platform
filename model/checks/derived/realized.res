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

/** A name a column fills by `Beneath`, the deployment named and the name taken there, btzlt. */
type below = {filled: string, deployment: string, name: string}

/**
 * What stands beneath one graph, btzlt. Design-wide every edge marked `beneath` reaches it, a
 * column with no `Beneath` has none, and in one holding some it stands for the deployment named.
 */
type under =
  | Anywhere
  | Nothing
  | Below(array<below>)

/** The blocks one graph is derived from, by main name, what each declares, and what is beneath. */
type running = {mains: array<string>, declared: dict<Provided.block>, under?: under}

/** Every block with its code, the as-built graph's when no deployment is named. */
let built = {mains, declared: Provided.all}

let underOf = (r: running) => r.under->Option.getOr(Anywhere)

/** The names a graph has filled by the platform beneath, each with what it takes down. */
let belowOf = (r: running) =>
  switch underOf(r) {
  | Below(fills) => fills
  | Anywhere | Nothing => []
  }

let declaredOf = (r: running, main) => r.declared->Dict.get(main)

/** The names a block provides, its main name first. */
let provides = (r, main) =>
  [main]->Array.concat(declaredOf(r, main)->Option.mapOr([], b => b.provides))

/** Whether a `Beneath` fills a name in the graph `r` derives, btzlt. */
let fromBeneath = (r, name) => belowOf(r)->Array.some(b => b.filled == name)

/** The blocks providing a name, by their main names, and `beneath` where a `Beneath` fills it. */
let providers = (r: running, name) =>
  r.mains
  ->Array.filter(m => provides(r, m)->Array.includes(name))
  ->Array.concat(fromBeneath(r, name) ? [beneath] : [])

/**
 * A name as the as-built graph knows it, each block providing it, or the name itself, its own node
 * kept where a `Beneath` fills it.
 */
let realize = (r, name) =>
  switch providers(r, name)->Array.map(m => m == beneath ? name : m) {
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
let retarget = (~pointed=Map.make(), r, own: array<string>, edge: Components.edge) =>
  if edge.beneath == Some(true) {
    underOf(r) == Nothing ? [] : [{...edge, to_: beneath}]
  } else if own->Array.includes(edge.to_) {
    []
  } else {
    let carried = edge.to_->String.startsWith("?") && edge.contract->Option.getOr([]) == []
    realize(r, edge.to_)->Array.map(t => {
      let moved =
        carried && t != edge.to_ ? {...edge, to_: t, contract: [edge.to_]} : {...edge, to_: t}
      if t != edge.to_ && !known(edge.to_) {
        pointed->Map.set(moved, edge.to_)
      }
      moved
    })
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

/** The interfaces a block answers as a boundary it provides, b75yr. */
let interfacesOf = n =>
  Boundaries.boundaries->Dict.get(n)->Option.flatMap(b => b.interfaces)->Option.getOr([])

/** An as-built graph's nodes, and the boundary each edge retargeted to its provider pointed to. */
type derived = {nodes: dict<Components.component>, pointed: Map.t<Components.edge, string>}

/**
 * The as-built graph of `nodes` with the blocks `r` running, a block merged from every name it
 * provides, and a name no block provides, or one filled from beneath, kept with none of its edges.
 */
let derived = (r: running, nodes: dict<Components.component>): derived => {
  let pointed = Map.make()
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
        ->Array.flatMap(e => retarget(~pointed, r, names, e))
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
    ->Array.filter(((n, _)) => fromBeneath(r, n) || providers(r, n) == [])
    ->Array.map(((n, c)) => (n, {...c, edges: []}))
  // Beneath answers its own products alone, each name filled from it standing apart, btzlt.
  let below = underOf(r) == Nothing ? [] : [(beneath, Provided.beneath)]
  {
    nodes: Array.concatMany(merged, [standing, below])
    ->Array.toSorted(((a, _), (b, _)) => byText(a, b))
    ->Dict.fromArray,
    pointed,
  }
}

/** The nodes of the as-built graph of `nodes` with the blocks `r` running. */
let derive = (r, nodes) => derived(r, nodes).nodes

/**
 * The as-built graph of the blocks `r` running over the design's `nodes`, its records written by
 * each writer's providers, each name filled from beneath marked.
 */
let graphIn = (r: running, ~nodes=components, ~own=Components.own) => {
  let {nodes, pointed} = derived(r, nodes)
  {
    components: nodes,
    own: derive(r, own),
    // A block named for a driver role is the drivers given filling it, RFC 7ykg6, no component.
    fillers: role =>
      design.fillers(role)->Array.concat(
        providers(r, role)
        // A role filled from beneath is its own node, as the design draws it.
        ->Array.map(m => m == beneath ? role : m)
        ->Array.filter(m => m != role || Drivers.asked->Dict.get(role)->Option.isNone)
        ->Array.filterMap(m => nodes->Dict.get(m)->Option.map(c => (m, c))),
      ),
    records: Records.records->Array.map(held => {
      ...held,
      writes: union(held.writes->Array.map(n => realize(r, n))),
    }),
    below: belowOf(r)->Array.map(b => b.filled),
    // A boundary's interfaces answer an edge that pointed to it, never one to its provider.
    answering: x => pointed->Map.get(x)->Option.mapOr([], interfacesOf),
  }
}

let graphOf = r => graphIn(r)

/** The as-built graph of every block with its code. */
let graph = graphOf(built)

/** The main names of the blocks a deployment's names are filled by, RFC vgvx6. */
let blocksIn = (d: Provided.deployed) =>
  union([
    d.fills->Array.filterMap(((_, f)) =>
      switch f {
      | Block(main) => Some(main)
      | Vendor(_) | Workload(_) | Beneath(_) => None
      }
    ),
  ])->Array.toSorted(byText)

/** The names a deployment fills by the platform beneath, each with what it takes down, btzlt. */
let filledBeneath = (d: Provided.deployed) =>
  d.fills->Array.filterMap(((filled, f)) =>
    switch f {
    | Beneath({deployment, name}) => Some({filled, deployment, name})
    | Block(_) | Vendor(_) | Workload(_) => None
    }
  )

/**
 * The blocks running in a deployment, those its names are filled by whose code is written, and the
 * platform beneath where a `Beneath` fills a name, none where none does.
 */
let runningIn = (d: Provided.deployed) => {
  mains: blocksIn(d)->Array.filter(m => mains->Array.includes(m)),
  declared: Provided.all,
  under: switch filledBeneath(d) {
  | [] => Nothing
  | fills => Below(fills)
  },
}

/** The names a deployment fills by a vendor's resource or a workload, each with what fills it. */
let filledApart = (d: Provided.deployed) =>
  d.fills->Array.filterMap(((name, f)) =>
    switch f {
    | Block(_) | Beneath(_) => None
    | Vendor({vendor, resource}) => Some((name, `${resource}, a resource of ${vendor}`))
    | Workload(what) => Some((name, `${what}, a workload`))
    }
  )
