/*** A name a column fills from the platform beneath, derived and checked, RFC btzlt. */
open Testing

let node = (layer, edges): Components.component => {layer, edges, uses: []}
let to = (to_, ~contract=?) => Components.e(to_, #serve, Components.hard, "made here", ~contract?)

let edgesOf = (g: dict<Components.component>, n) =>
  g->Dict.get(n)->Option.mapOr([], c => c.edges->Array.map(e => (e.to_, e.contract)))

let over = (components): Base.graph => {
  components,
  own: components,
  fillers: _ => [],
  records: [],
}

/** What a check finds over a graph from the node `from`, by its text. */
let foundFrom = (c: Base.checked, from) =>
  c.violations->Array.map(v => v.text)->Array.filter(t => t->String.startsWith(`${from} ->`))

let column = (fills): Provided.deployed => {fills, targets: []}

let fill = (filled, deployment, name): Realized.below => {filled, deployment, name}

let under = (fills, ~mains=["c"], ~declared=dict{}): Realized.running => {
  mains,
  declared,
  under: Below(fills),
}

let filled: Components.component = {
  layer: Components.vendor,
  kind: #ground,
  half: #organization,
  answers: ["footing"],
  edges: [to("elsewhere")],
  uses: [],
}

let marked = (contract): Components.edge => {...to("down", ~contract=[contract]), beneath: true}

let graph = dict{
  "c": node(0, [to("f", ~contract=["footing"]), to("f", ~contract=["configuration"])]),
  "f": filled,
}

let derived = (~extra=[], r: Realized.running) =>
  Realized.derive({...r, declared: dict{"c": {provides: [], extra}}}, graph)

/** The as-built graph of `graph`, each name filled from beneath marked. */
let marking = (~extra=[], r: Realized.running) =>
  Realized.graphIn({...r, declared: dict{"c": {provides: [], extra}}}, ~nodes=graph, ~own=graph)

test("a name filled by Beneath keeps its own node, beneath answering its products alone", () => {
  let r = under([fill("f", "lower", "x")])
  deepEqual(Realized.providers(r, "f"), ["beneath"])
  deepEqual(Realized.fromBeneath(r, "f"), true)
  let g = derived(r, ~extra=[marked("?relay")])
  deepEqual(
    edgesOf(g, "c"),
    [("f", Some(["footing"])), ("f", Some(["configuration"])), ("beneath", Some(["?relay"]))],
  )
  deepEqual(g->Dict.get("f"), Some({...filled, edges: []}))
  deepEqual(marking(r).below, Some(["f"]))
  deepEqual(
    g->Dict.get("beneath")->Option.flatMap(c => c.answers),
    Some(["storage", "database", "wit"]),
  )
})

test("a scaffold's line keeps the name filled from beneath, marked as from beneath", () => {
  deepEqual(
    foundFrom(Crossing.check(marking(under([fill("f", "lower", "x")]))), "c"),
    ["c -> f (beneath): configuration, which f does not answer"],
  )
  deepEqual(
    foundFrom(Crossing.check(marking({...Realized.built, mains: ["c"]})), "c"),
    ["c -> f: configuration, which f does not answer"],
  )
})

test("an edge marked beneath is judged by the products beneath alone", () =>
  deepEqual(
    foundFrom(
      Crossing.check(marking(under([fill("f", "lower", "x")]), ~extra=[marked("footing")])),
      "c",
    ),
    [
      "c -> f (beneath): configuration, which f does not answer",
      "c -> beneath: footing, which beneath does not answer",
    ],
  )
)

test("an edge marked beneath is no edge in a column with no Beneath", () => {
  let g = derived(Realized.runningIn(column([("c", Block("c"))])), ~extra=[marked("?relay")])
  deepEqual(g->Dict.get("beneath"), None)
  deepEqual(Realized.runningIn(column([("c", Block("c"))])).under, Some(Nothing))
})

test("an edge marked beneath reaches beneath outside any deployment's view", () => {
  let g = derived({...Realized.built, mains: ["c"]}, ~extra=[marked("?relay")])
  deepEqual(
    edgesOf(g, "c"),
    [("f", Some(["footing"])), ("f", Some(["configuration"])), ("beneath", Some(["?relay"]))],
  )
})

test("the half rules and the half across read the filled name's own half", () => {
  let halves = dict{
    "o": {...node(0, [to("p")]), half: #organization},
    "p": {...node(0, []), half: #platform},
  }
  let g = Realized.graphIn(
    under([fill("p", "lower", "x")], ~mains=["o"]),
    ~nodes=halves,
    ~own=halves,
  )
  deepEqual(
    Rules.check(g).violations
    ->Array.map(v => v.text)
    ->Array.filter(t => t->String.includes("o -> p")),
    ["the organization's half needs the platform's: o -> p (beneath) serve/hard: made here"],
  )
  deepEqual(Crossing.halfAcross(g, Some(#organization), "p"), Some(#platform))
})

test("a role filled from beneath is filled by its own node, as the design draws it", () => {
  let g = Realized.graphOf({
    mains: [],
    declared: Provided.all,
    under: Below([fill("authority", "lower", "x")]),
  })
  deepEqual(g.fillers("authority")->Array.map(((n, _)) => n), ["authority"])
  deepEqual(
    Roles.check(g).violations
    ->Array.map(v => v.text)
    ->Array.filter(t => t->String.includes("fills authority")),
    [],
  )
})

let lookup = n =>
  dict{
    "runs": {...node(0, []), answers: ["wit"]},
    "keeps": {...node(0, []), answers: ["footing"]},
    "storage": node(1, []),
    "database": node(0, []),
  }->Dict.get(n)

test("a product at layer 0 passes check two by its own name or any of its answers", () => {
  deepEqual(Derivations.throughProduct(~lookup, "database"), true)
  deepEqual(Derivations.throughProduct(~lookup, "runs"), true)
  deepEqual(Derivations.throughProduct(~lookup, "keeps"), false)
  deepEqual(Derivations.throughProduct(~lookup, "storage"), false)
  deepEqual(Derivations.throughProduct(~lookup, "nothing"), false)
  deepEqual(Derivations.throughProduct("compute"), true)
})

test(
  "a name taken down by Beneath is a product at layer 0 beneath answers, else against 94y0d",
  () => {
    let d = column([
      ("footing(organization)", Beneath({deployment: "lower", name: "control(organization)"})),
      ("blob", Beneath({deployment: "lower", name: "database"})),
      ("app", Beneath({deployment: "lower", name: "compute"})),
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
    let unbuilt = column([("u", Block("u"))])
    let declared = dict{"u": ({provides: ["?thing"], extra: []}: Provided.block)}
    deepEqual(Derivations.providedThere(~declared, unbuilt, "?thing"), true)
    deepEqual(Derivations.providedThere(~declared, unbuilt, "?other"), false)
  },
)

/** Answers nothing, so a test of check one alone has no contract to leave unanswered. */
let bare = _ => None

let mistaken = (~lookup=bare, ~deployments, column_, fills) =>
  Derivations.mistakenBeneath(~deployments, ~lookup, column_, column(fills))->Array.map(f => (
    f.at,
    f.text,
  ))

test("a Beneath names one deployment that exists, provides the name, and is not its own", () => {
  let deployments = dict{"lower": lower, "upper": column([])}
  let mistaken = fills => mistaken(~deployments, "upper", fills)
  deepEqual(mistaken([("footing(organization)", Beneath({deployment: "lower", name: "app"}))]), [])
  deepEqual(
    mistaken([("footing(organization)", Beneath({deployment: "lower", name: "database"}))]),
    [
      (
        ["footing(organization)"],
        "footing(organization) is filled by database in lower, which provides it not there",
      ),
    ],
  )
  deepEqual(
    mistaken([("footing(organization)", Beneath({deployment: "upper", name: "app"}))]),
    [
      (
        ["footing(organization)"],
        "footing(organization) is filled from beneath by upper, the deployment's own",
      ),
    ],
  )
  deepEqual(
    mistaken([
      ("footing(organization)", Beneath({deployment: "lower", name: "app"})),
      ("storage", Beneath({deployment: "nowhere", name: "storage"})),
    ]),
    [
      (
        ["footing(organization)", "storage"],
        "upper stands on lower, nowhere, more than one deployment beneath",
      ),
      (["storage"], "storage is filled from beneath by nowhere, which is no deployment"),
    ],
  )
})

test("check one follows a chain of Beneath to its end", () => {
  let chain = last =>
    dict{
      "b": column([("g", Beneath({deployment: "c", name: "h"}))]),
      "c": column(last),
    }
  deepEqual(
    mistaken(
      ~deployments=chain([("h", Workload("w"))]),
      "a",
      [("f", Beneath({deployment: "b", name: "g"}))],
    ),
    [],
  )
  deepEqual(
    mistaken(~deployments=chain([]), "a", [("f", Beneath({deployment: "b", name: "g"}))]),
    [(["f"], "f is filled by g in b, a chain ending at h in c, which provides it not there")],
  )
})

test("a chain coming back to a column already passed is mistaken", () => {
  let fills = [("f", Provided.Beneath({deployment: "b", name: "g"}))]
  deepEqual(
    mistaken(
      ~deployments=dict{"b": column([("g", Beneath({deployment: "a", name: "f"}))])},
      "a",
      fills,
    ),
    [(["f"], "a stands on a chain of deployments coming back to one passed, a -> b -> a")],
  )
  deepEqual(
    mistaken(
      ~deployments=dict{
        "b": column([("g", Workload("w")), ("y", Beneath({deployment: "a", name: "z"}))]),
      },
      "a",
      fills,
    ),
    [(["f"], "a stands on a chain of deployments coming back to one passed, a -> b -> a")],
  )
  deepEqual(
    mistaken(
      ~deployments=dict{"b": column([("g", Beneath({deployment: "b", name: "h"}))])},
      "a",
      fills,
    ),
    [(["f"], "f is filled by g in b, a chain coming back to b, already passed")],
  )
})

test("every contract the filled name answers must be answered by the name taken", () => {
  let deployments = dict{
    "lower": column([("database", Workload("w")), ("keeps", Workload("w"))]),
    "upper": column([]),
  }
  let taken = name =>
    mistaken(
      ~lookup=Base.component,
      ~deployments,
      "upper",
      [("footing(organization)", Beneath({deployment: "lower", name}))],
    )
  deepEqual(
    taken("database"),
    [
      (
        ["footing(organization)"],
        "footing(organization) is filled by database in lower, which leaves footing, records, bundle unanswered",
      ),
    ],
  )
  let lookup = n =>
    switch n {
    | "footing(organization)" => Base.component(n)
    | "keeps" => Some({...node(0, []), answers: ["bundle", "footing", "records", "more"]})
    | "partial" => Some({...node(0, []), answers: ["footing"]})
    | _ => None
    }
  let by = name =>
    mistaken(
      ~lookup,
      ~deployments=dict{"lower": column([("keeps", Workload("w")), ("partial", Workload("w"))])},
      "upper",
      [("footing(organization)", Beneath({deployment: "lower", name}))],
    )
  deepEqual(by("keeps"), [])
  let d = column([("footing(organization)", Beneath({deployment: "lower", name: "database"}))])
  let v = Derivations.viewOf(~deployments, "upper", d)
  deepEqual(v.wrongBelow("footing(organization)"), true)
  deepEqual(
    by("partial"),
    [
      (
        ["footing(organization)"],
        "footing(organization) is filled by partial in lower, which leaves records, bundle unanswered",
      ),
    ],
  )
  deepEqual(Derivations.unanswered(~lookup, "footing(organization)", "footing(organization)"), [])
})

test("a column's report names a contract left unanswered beside what else it finds", () => {
  let deployments = dict{"lower": column([])}
  deepEqual(
    mistaken(
      ~lookup=Base.component,
      ~deployments,
      "upper",
      [("footing(organization)", Beneath({deployment: "lower", name: "database"}))],
    ),
    [
      (
        ["footing(organization)"],
        "footing(organization) is filled by database in lower, which provides it not there",
      ),
      (
        ["footing(organization)"],
        "footing(organization) is filled by database in lower, which leaves footing, records, bundle unanswered",
      ),
    ],
  )
})

/** The Frontier's waiting line over a column filling `storage` by `name` in the column beneath. */
let waiting = (name, beneath) => {
  let d = column([("storage", Beneath({deployment: "lower", name}))])
  Derivations.frontierLines(Derivations.viewOf(~deployments=dict{"lower": beneath}, "upper", d))
  ->Array.filter(l => l->String.startsWith("waiting: "))
  ->Array.some(l => l->String.includes("storage on"))
}

test("a name filled through a Beneath found wrong is not rightly provided", () => {
  deepEqual(waiting("database", column([("database", Workload("w"))])), false)
  deepEqual(waiting("control(organization)", lower), true)
  deepEqual(waiting("compute", lower), true)
})

test("a column's view and Provided report carry what its Beneath fills find", () => {
  let deployments = dict{"lower": lower}
  let upper = fills => column(fills)
  let wrong = upper([
    ("footing(organization)", Beneath({deployment: "lower", name: "control(organization)"})),
  ])
  let v = Derivations.viewOf(~deployments, "upper", wrong)
  deepEqual(
    v.scaffolds
    ->Array.filter(((title, _)) => title == "Beneath")
    ->Array.map(((_, f)) => f.text),
    [
      "upper fills footing(organization) by control(organization) in lower, no product at layer 0 beneath answers, against RFC 94y0d",
    ],
  )
  deepEqual(v.wrongBelow("footing(organization)"), true)
  deepEqual(v.wrongBelow("storage"), false)
  let lines = (d: Provided.deployed) =>
    Derivations.providedLines(
      ~deployments,
      "upper",
      Derivations.viewOf(~deployments, "upper", d),
      d,
    )
  deepEqual(
    lines(wrong)->Array.filter(l => l->String.startsWith("footing(organization)")),
    [
      "footing(organization): beneath, control(organization) in lower",
      "footing(organization) is filled by control(organization) in lower, which leaves footing, records, bundle unanswered",
    ],
  )
  deepEqual(lines(wrong)->Array.filter(l => l->String.startsWith("storage:")), ["storage: none"])
  let missing = upper([("footing(organization)", Beneath({deployment: "lower", name: "database"}))])
  deepEqual(
    lines(missing)->Array.filter(l => l->String.startsWith("footing(organization)")),
    [
      "footing(organization): beneath, database in lower",
      "footing(organization) is filled by database in lower, which provides it not there",
      "footing(organization) is filled by database in lower, which leaves footing, records, bundle unanswered",
    ],
  )
})

test("the Provided report lists every name a column fills, a trusted one too", () => {
  let d = column([
    ("footing(organization)", Vendor({vendor: "cloud", resource: "a table"})),
    ("app", Workload("hello")),
  ])
  let lines = Derivations.providedLines(
    ~deployments=dict{},
    "upper",
    Derivations.viewOf(~deployments=dict{}, "upper", d),
    d,
  )
  deepEqual(
    lines->Array.filter(l =>
      l->String.startsWith("footing(organization)") || l->String.startsWith("app")
    ),
    ["app: hello, a workload", "footing(organization): a table, a resource of cloud"],
  )
  deepEqual(lines->Array.some(l => l->String.startsWith("vendor")), false)
})

test(
  "a boundary's interfaces answer only an edge to the boundary, never one straight to its block",
  () => {
    let nodes = dict{
      "h": node(-2, [to("?roster", ~contract=["bindings"]), to("k", ~contract=["bindings"])]),
      "k": node(0, []),
    }
    let g = Realized.graphIn(
      {mains: ["h", "k"], declared: dict{"k": {provides: ["?roster"], extra: []}}},
      ~nodes,
      ~own=nodes,
    )
    deepEqual(edgesOf(g.components, "h"), [("k", Some(["bindings"])), ("k", Some(["bindings"]))])
    deepEqual(g.components->Dict.get("k")->Option.flatMap(c => c.answers), Some(["?roster"]))
    deepEqual(foundFrom(Crossing.check(g), "h"), ["h -> k: bindings, which k does not answer"])
  },
)
