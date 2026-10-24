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
