/*** The as-built graph derived of a design and the blocks running, and of a deployment's fills. */
open Testing

let node = (layer, edges): Components.component => {layer, edges, uses: []}
let to = (to_, ~contract=?) => Components.e(to_, #serve, Components.hard, "made here", ~contract?)

let nodes = dict{
  "a": node(0, [to("b"), to("?x")]),
  "b": node(-1, [to("c")]),
  "c": node(-2, []),
  "d": node(0, [to("?x")]),
}

let edgesOf = (g: dict<Components.component>, n) =>
  g->Dict.get(n)->Option.mapOr([], c => c.edges->Array.map(e => (e.to_, e.contract)))

let running: Realized.running = {
  mains: ["a"],
  declared: dict{"a": {provides: ["?x"], extra: []}},
}

test("a block keeps its names' edges and none internal to it", () => {
  let g = Realized.derive(running, nodes)
  deepEqual(g->Dict.keysToArray, ["a", "b", "beneath", "c", "d"])
  deepEqual(edgesOf(g, "a"), [("b", None)])
  deepEqual(g->Dict.get("a")->Option.flatMap(c => c.answers), Some(["?x"]))
})

test("a name no block provides keeps its node and none of its edges", () => {
  let g = Realized.derive(running, nodes)
  deepEqual(edgesOf(g, "b"), [])
  deepEqual(edgesOf(g, "d"), [])
})

test("an edge to a boundary a block provides carries the boundary as its contract", () => {
  let g = Realized.derive({...running, mains: ["a", "d"]}, nodes)
  deepEqual(edgesOf(g, "d"), [("a", Some(["?x"]))])
})

test("a block not running provides nothing, though declared", () => {
  let g = Realized.derive({...running, mains: ["b"]}, nodes)
  deepEqual(edgesOf(g, "a"), [])
  deepEqual(edgesOf(g, "b"), [("c", None)])
})

let deployed: Provided.deployed = {
  fills: [
    ("control(organization)", Block("control(organization)")),
    ("footing(organization)", Vendor({vendor: "cloudflare", resource: "the D1 database"})),
    ("app", Workload("hello")),
    ("nothing", Block("no such component")),
  ],
  targets: ["root@machine.example"],
}

test("a deployment runs the blocks its names are filled by, the design naming them", () =>
  deepEqual(Realized.runningIn(deployed).mains, ["control(organization)"])
)

test("a name a vendor or a workload fills is provided apart, its text kept", () =>
  deepEqual(
    Realized.filledApart(deployed),
    [
      ("footing(organization)", "the D1 database, a resource of cloudflare"),
      ("app", "hello, a workload"),
    ],
  )
)

test("a name not filled is provided by none, though a block with code provides it", () => {
  deepEqual(Realized.providers(Realized.built, "control(organization)"), ["control(organization)"])
  deepEqual(
    Realized.providers(Realized.runningIn({fills: [], targets: []}), "control(organization)"),
    [],
  )
})

test("a block filling a name runs only where its code is written", () =>
  deepEqual(Realized.runningIn({fills: [("compute", Block("compute"))], targets: []}).mains, [])
)

let over = (components): Base.graph => {
  components,
  own: components,
  fillers: _ => [],
  records: [],
}

test("a block named for a role is held by the rules as a component is", () => {
  let roled = dict{
    "r": ({layer: -2, kind: #provided, edges: [], uses: []}: Components.component),
    "h": node(-2, [to("up")]),
    "up": node(0, []),
  }
  let g = Realized.derive({mains: ["r"], declared: dict{"r": {provides: ["h"], extra: []}}}, roled)
  deepEqual(g->Dict.get("r")->Option.flatMap(c => c.kind), None)
  deepEqual(
    Rules.check(over(g)).violations->Array.map(v => v.text),
    ["r -> up serve/hard: made here"],
  )
})

test("a block named for a driver role is the drivers given filling it, no component", () => {
  let fillersOf = (r: Realized.running) =>
    Realized.graphOf(r).fillers("driver(machine)")->Array.map(((name, _)) => name)
  deepEqual(
    fillersOf({
      mains: ["driver(machine)"],
      declared: dict{"driver(machine)": {provides: ["host"], extra: []}},
    }),
    [],
  )
  deepEqual(
    fillersOf({
      mains: ["driver(machine)", "host"],
      declared: dict{"host": {provides: ["driver(machine)"], extra: []}},
    }),
    ["host"],
  )
})

let column = (fills): Provided.deployed => {fills, targets: []}

let below = {
  let graph = dict{
    "c": node(0, [to("f", ~contract=["held"])]),
    "f": {layer: Components.vendor, kind: #ground, answers: ["held"], edges: [], uses: []},
  }
  let marked = {...to("down", ~contract=["?relay"]), beneath: true}
  let declared = dict{"c": ({provides: [], extra: [marked]}: Provided.block)}
  (r: Realized.running) => Realized.derive({...r, mains: ["c"], declared}, graph)
}

let underneath = Realized.runningIn(
  column([("f", Beneath({deployment: "lower", name: "c"})), ("c", Block("c"))]),
)

test("a name filled by Beneath is provided by beneath, which answers what it answers", () => {
  deepEqual(Realized.providers(underneath, "f"), ["beneath"])
  let g = below(underneath)
  deepEqual(edgesOf(g, "c"), [("beneath", Some(["held"])), ("beneath", Some(["?relay"]))])
  deepEqual(
    g->Dict.get("beneath")->Option.flatMap(c => c.answers),
    Some(["storage", "database", "wit", "held"]),
  )
  deepEqual(g->Dict.get("f"), None)
})

test("an edge marked beneath is no edge in a column with no Beneath", () => {
  let g = below(Realized.runningIn(column([("c", Block("c"))])))
  deepEqual(edgesOf(g, "c"), [("f", Some(["held"]))])
  deepEqual(g->Dict.get("beneath"), None)
})

test("an edge marked beneath reaches beneath outside any deployment's view", () => {
  let g = below(Realized.built)
  deepEqual(edgesOf(g, "c"), [("f", Some(["held"])), ("beneath", Some(["?relay"]))])
  deepEqual(
    g->Dict.get("beneath")->Option.flatMap(c => c.answers),
    Some(["storage", "database", "wit"]),
  )
})

test("a deployment's names filled by Beneath are taken apart from its blocks", () => {
  let d = column([
    ("f", Beneath({deployment: "lower", name: "c"})),
    ("c", Block("control(organization)")),
  ])
  deepEqual(Realized.filledBeneath(d), [{filled: "f", deployment: "lower", name: "c"}])
  deepEqual(Realized.blocksIn(d), ["control(organization)"])
  deepEqual(Realized.filledApart(d), [])
})

let lower = column([
  ("app", Workload("hello")),
  ("control(organization)", Block("control(organization)")),
])

test(
  "a name taken down is provided where a block there provides it or a fill there fills it",
  () => {
    deepEqual(Derivations.providedThere(lower, "app"), true)
    deepEqual(Derivations.providedThere(lower, "?roster"), true)
    deepEqual(Derivations.providedThere(lower, "database"), false)
  },
)

test("a Beneath names one deployment that exists, provides the name, and is not its own", () => {
  let deployments = dict{"lower": lower, "upper": column([])}
  let mistaken = fills => Derivations.mistakenBeneath(~deployments, "upper", column(fills))
  deepEqual(mistaken([("footing(organization)", Beneath({deployment: "lower", name: "app"}))]), [])
  deepEqual(
    mistaken([("footing(organization)", Beneath({deployment: "lower", name: "database"}))]),
    ["footing(organization) is filled by database in lower, which provides it not there"],
  )
  deepEqual(
    mistaken([("footing(organization)", Beneath({deployment: "upper", name: "app"}))]),
    ["footing(organization) is filled from beneath by upper, the deployment's own"],
  )
  deepEqual(
    mistaken([
      ("footing(organization)", Beneath({deployment: "lower", name: "app"})),
      ("storage", Beneath({deployment: "nowhere", name: "storage"})),
    ]),
    [
      "upper stands on lower, nowhere, more than one deployment beneath",
      "storage is filled from beneath by nowhere, which is no deployment",
    ],
  )
})

test(
  "a name taken down by Beneath is a product at layer 0 beneath answers, else against 94y0d",
  () => {
    let d = column([
      ("footing(organization)", Beneath({deployment: "lower", name: "control(organization)"})),
      ("blob", Beneath({deployment: "lower", name: "database"})),
    ])
    deepEqual(
      Derivations.downward("upper", d)->Array.map(((title, f)) => (title, f.at, f.text)),
      [
        (
          "Beneath",
          ["footing(organization)"],
          "upper fills footing(organization) by control(organization) in lower, no product at layer 0 beneath answers, against RFC 94y0d",
        ),
      ],
    )
  },
)
