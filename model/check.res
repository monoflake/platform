/**
 * Runs s0's dimensions over the model, `scope.md`: D0 serve, D1 bootstrap, D2 restart, D3 upgrade
 * and D5 contract, each printing its question, every violation, and every assumption -- an edge to
 * a boundary whose contract is written -- and then the bootstrap path, RFC 94y0d, and the
 * checklist. D4 recovery models a failure, so it is s1's, and runs only with `--s1`. With
 * `--ready`, or `--ready=N`, the checklist fails while a row that blocks step 0, or step N, is
 * open, or an open question names no row. Exits 1 when any dimension finds a violation.
 */
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
let parts = Graph.parts
let part = n => parts->Dict.get(n)
let edgesOf = n => part(n)->Option.mapOr([], p => p.edges)
let boundary = n => Graph.boundaries->Dict.get(n)
let num = Float.toString
let int = Int.toString
let byText = (a: string, b: string) => a < b ? -1. : a > b ? 1. : 0.

let layerName = layer =>
  layer == Graph.vendor ? "ground" : layer > 0 ? `+${int(layer)}` : int(layer)
let known = to_ => !(to_->String.startsWith("?"))
let tag = (edge: Graph.edge) => `${(edge.when_ :> string)}/${edge.hard ? "hard" : "soft"}`
let designed = parts->Dict.toArray->Array.filter(((_, p)) => p.kind == None)
let line = (from, edge: Graph.edge) => `${from} -> ${edge.to_} ${tag(edge)}: ${edge.why}`
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
let order = (when_: Graph.edge => bool): array<string> => {
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
let atBoundaries = (when_: Graph.edge => bool): split => {
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

// The rules every dimension stands on: a hard edge points to its own layer or below, a library uses
// only libraries, and no hard edge closes a cycle.
let rules = []
let softUp = []
designed->Array.forEach(((name, p)) => {
  p.edges->Array.forEach(edge =>
    if known(edge.to_) {
      switch part(edge.to_) {
      | None => rules->Array.push(`${name} -> ${edge.to_}: no such part`)
      | Some(target) =>
        if target.layer > p.layer && target.kind == None {
          (edge.hard ? rules : softUp)->Array.push(line(name, edge))
        }
      }
    }
  )
  p.uses->Array.forEach(lib =>
    if Graph.libraries->Dict.get(lib) == None {
      rules->Array.push(`${name} uses ${lib}: no such library`)
    }
  )
})
Graph.libraries
->Dict.toArray
->Array.forEach(((name, lib)) =>
  lib.uses->Array.forEach(use =>
    if Graph.libraries->Dict.get(use) == None {
      rules->Array.push(`${name} uses ${use}: a part`)
    }
  )
)
// The platform runs on itself only while the graph is clean: nothing at layer 0 or below has an edge,
// hard or soft, to what it runs as an owner, RFC vuanj.
designed->Array.forEach(((name, p)) =>
  if p.layer <= 0 {
    p.edges->Array.forEach(edge =>
      if part(edge.to_)->Option.flatMap(t => t.asOwner)->Option.getOr(false) {
        rules->Array.push(`runs as an owner, needed below: ${line(name, edge)}`)
      }
    )
  }
)
// The organization's half runs on while the platform's cannot be reached: none of its parts needs the
// platform's to serve or to start, and reads a bundle instead, RFC v7v3w.
let halfOf = to_ =>
  known(to_) ? part(to_)->Option.flatMap(p => p.half) : boundary(to_)->Option.flatMap(b => b.half)
designed->Array.forEach(((name, p)) =>
  if p.half == Some(#organization) {
    p.edges->Array.forEach(edge =>
      if (edge.when_ == #serve || edge.when_ == #start) && halfOf(edge.to_) == Some(#platform) {
        rules->Array.push(`the organization's half needs the platform's: ${line(name, edge)}`)
      }
    )
  }
)
// What the platform's half holds is configuration, written on the control plane alone, so the data
// plane runs on while the control plane is lost, `scope.md`.
let isControl = n => part(n)->Option.flatMap(p => p.control)->Option.getOr(false)
Graph.records
->Dict.toArray
->Array.forEach(((name, r)) => {
  let config = r.half == #platform || r.writes->Array.some(isControl)
  r.writes->Array.forEach(w =>
    switch part(w) {
    | None => rules->Array.push(`${w} writes ${name}: no such part`)
    | Some(writer) =>
      if config && !isControl(w) {
        rules->Array.push(`the data plane writes configuration: ${w} writes ${name}, ${r.from}`)
      } else if r.half == #platform && writer.half != Some(#platform) {
        rules->Array.push(`an organization writes the platform's: ${w} writes ${name}, ${r.from}`)
      }
    }
  )
})
// A footing is the platform's or an organization's, and each half stands on its own alone, by any
// edge, RFC vr5lw.
designed->Array.forEach(((name, p)) =>
  p.edges->Array.forEach(edge =>
    switch part(edge.to_) {
    | Some(t) if t.kind == Some(#ground) && t.half != None && t.half != p.half =>
      rules->Array.push(`stands on the other half's footing: ${line(name, edge)}`)
    | _ => ()
    }
  )
)
let hardNext = n => edgesOf(n)->Array.filter(x => x.hard && known(x.to_))->Array.map(x => x.to_)
cycles(hardNext, parts->Dict.keysToArray)->Array.forEach(c => rules->Array.push(`hard cycle: ${c}`))
cycles(
  n => Graph.libraries->Dict.get(n)->Option.mapOr([], l => l.uses),
  Graph.libraries->Dict.keysToArray,
)->Array.forEach(c => rules->Array.push(`library cycle: ${c}`))
let orNone = (xs, sep) => xs->Array.length > 0 ? xs->Array.join(sep) : "none"
dimension(
  "Rules",
  "Does every hard edge point down, every library use only libraries, nothing below need an owner, no organization need the platform's half to serve or start, the data plane write no configuration, and each half stand on its own footing alone?",
  rules,
  ~notes=[
    `soft edges upward, allowed: ${softUp->orNone("; ")}`,
    `no half, since they run nothing: ${designed
      ->Array.filter(((_, p)) => p.half == None)
      ->Array.map(((n, _)) => n)
      ->orNone(", ")}`,
  ],
  (),
)

let serve = (x: Graph.edge) => x.when_ == #serve
let d0 = atBoundaries(serve)
dimension(
  "D0 Serve",
  "On the correct path, does every operation the products promise reach the ground?",
  d0.violations,
  ~assumed=d0.assumed,
  (),
)

let firstUp = (x: Graph.edge) => x.when_ == #start || x.when_ == #deploy
let d1 = atBoundaries(firstUp)
dimension(
  "D1 Bootstrap",
  "From the ground and the operator alone, can every part come up the first time?",
  Array.concat(
    cycles(
      n => edgesOf(n)->Array.filter(x => firstUp(x) && known(x.to_))->Array.map(x => x.to_),
      parts->Dict.keysToArray,
    )->Array.map(c => `cycle: ${c}`),
    d1.violations,
  ),
  ~notes=[`order: ${order(firstUp)->Array.join(" -> ")}`],
  ~assumed=d1.assumed,
  (),
)

let start = (x: Graph.edge) => x.when_ == #start
let d2 = atBoundaries(start)
let rec reachesGround = (n, seen) =>
  if seen->Set.has(n) {
    false
  } else {
    seen->Set.add(n)
    edgesOf(n)->Array.some(x =>
      x.hard && known(x.to_) && (isGround(x.to_) || reachesGround(x.to_, seen))
    )
  }
let keeps = (p: Graph.part) => p.keeps->Option.getOr(false)
dimension(
  "D2 Restart",
  "After a planned stop of everything, can every part come back from what it kept?",
  Array.concat(
    designed
    ->Array.filter(((n, p)) => keeps(p) && !reachesGround(n, Set.make()))
    ->Array.map(((n, _)) => `${n} keeps state, but no hard edge carries it to the ground`),
    d2.violations,
  ),
  ~notes=[
    `order: ${order(start)->Array.join(" -> ")}`,
    `keep state of their own: ${designed
      ->Array.filter(((_, p)) => keeps(p))
      ->Array.map(((n, _)) => n)
      ->Array.join(", ")}`,
  ],
  ~assumed=d2.assumed,
  (),
)

let crossing =
  designed->Array.flatMap(((n, p)) =>
    p.edges->Array.filterMap(x => x.reads->Option.map(reads => (n, x, reads)))
  )
let replaces = (x: Graph.edge) => x.replaces->Option.getOr(false)
// What replaces a part is the edge marked `replaces`; an edge it deploys others by says nothing.
let d3 = atBoundaries(replaces)
dimension(
  "D3 Upgrade",
  "While the rest runs, can one part be replaced by a new version?",
  [
    designed
    ->Array.filter(((_, p)) => !(p.edges->Array.some(replaces)))
    ->Array.map(((n, _)) => `${n}: nothing says what replaces it`),
    designed->Array.flatMap(((n, p)) =>
      p.edges
      ->Array.filter(x => replaces(x) && x.to_ == n)
      ->Array.map(_ => `${n}: replacing it needs itself`)
    ),
    d3.violations,
    crossing
    ->Array.filter(((from, _, _)) =>
      !(part(from)->Option.mapOr([], p => p.uses)->Array.includes("compat*"))
    )
    ->Array.map(((from, _, reads)) => `${from} reads ${reads}'s format without compat*`),
  ]->Array.flat,
  ~notes=Graph.globalOpen->Array.map(g => `open: ${g}`),
  ~assumed=d3.assumed,
  (),
)

dimension(
  "D5 Contract",
  "Is every format a part reads defined at its own layer or below? Carried unread is exempt.",
  crossing
  ->Array.filter(((from, _, reads)) => layerOf(reads) > layerOf(from))
  ->Array.map(((from, edge, reads)) =>
    `${from} (${layerName(layerOf(from))}) reads ${reads} (${layerName(
        layerOf(reads),
      )})'s format: ${edge.why}`
  ),
  (),
)

// The bootstrap path, RFC 94y0d: each step holds, and each deployment came to it by a move it may
// take. A version, v, is the Platform's release; a stage, s, is the model's, `scope.md`.
let steps = Bootstrap.steps
let path = []
let stops = []
let ons = (d: Bootstrap.deployment, f) => d.on->Array.includes(f)
steps->Array.forEachWithIndex((step, i) => {
  let at = `step ${int(i)}`
  let before = steps[i - 1]
  let sides = [
    ("internal", Some(step.internal), before->Option.map(b => b.internal)),
    ("external", step.external_, before->Option.flatMap(b => b.external_)),
  ]
  sides->Array.forEach(((name, d, was)) =>
    switch d {
    | None => ()
    | Some(d) =>
      d.on->Array.forEach(
        f =>
          if !(Bootstrap.versions[d.version]->Option.mapOr(false, v => v->Array.includes(f))) {
            path->Array.push(
              `${at}: the ${name} platform turns on ${(f :> string)}, which v${int(
                  d.version,
                )} lacks`,
            )
          },
      )
      switch was {
      | None =>
        let first: Bootstrap.move = name == "internal" ? #"by hand" : #"new organization"
        if d.move != first {
          path->Array.push(
            `${at}: the ${name} platform first comes up by ${(d.move :> string)}, not ${(first :> string)}`,
          )
        }
      | Some(was) =>
        if d.version == was.version {
          if d.move != #none {
            path->Array.push(
              `${at}: the ${name} platform moves by ${(d.move :> string)} with no new version`,
            )
          }
        } else if d.move == #rolling && !ons(was, #rolling) {
          path->Array.push(
            `${at}: the ${name} platform rolls from v${int(
                was.version,
              )}, which cannot replace a part while the rest run`,
          )
        } else if d.move == #"planned stop" {
          stops->Array.push(
            `${at}, the ${name} platform, v${int(was.version)} -> v${int(d.version)}`,
          )
          if ons(was, #rolling) {
            path->Array.push(
              `${at}: the ${name} platform stops, though v${int(was.version)} can roll`,
            )
          }
        } else if d.move != #rolling {
          path->Array.push(`${at}: the ${name} platform changes version by ${(d.move :> string)}`)
        }
      }
      if d.ground->Array.includes(#provider) && !ons(d, #hosts) {
        path->Array.push(`${at}: the ${name} platform stands on machines without hosts turned on`)
      }
      // What its ground gives, RFC vr5lw: a footing of one kind of each class, for the platform's
      // control and each organization's alike, and extensions that give what the products need.
      let kinds = Resources.footingKinds(d)
      let held = Set.fromArray(kinds->Set.values->Array.fromIterator->Array.map(Resources.classOf))
      [#compute, #storage, #database]->Array.forEach(
        c =>
          if !(held->Set.has(c)) {
            path->Array.push(`${at}: the ${name} platform's footing has no ${(c :> string)}`)
          },
      )
      if !(kinds->Set.has(#function)) {
        path->Array.push(
          `${at}: the ${name} platform's footing gives no effect function for its control`,
        )
      }
      if ons(d, #products) {
        let given = Resources.extensionKinds(d)
        Resources.needs->Array.forEach(
          n =>
            if (
              !(
                n.any->Array.some(
                  k => given->Map.get(k)->Option.getOr(-1.) >= n.cpu->Option.getOr(0.),
                )
              )
            ) {
              path->Array.push(
                `${at}: the ${name} platform's extensions give none of ${n.any
                  ->Array.map(k => (k :> string))
                  ->Array.join(", ")}${switch n.cpu {
                  | Some(c) if c != 0. => ` with ${num(c)} ms of CPU a call`
                  | _ => ""
                  }}: ${n.why}`,
              )
            },
        )
      }
      Resources.unreached(d)->Array.forEach(
        r =>
          path->Array.push(
            `${at}: the ${name} platform's ${r} reaches the public network by no path`,
          ),
      )
    }
  )
  let a = step.internal
  let b = step.external_
  a.ground->Array.forEach(g =>
    if g == #home || g == #internal {
      path->Array.push(`${at}: the internal platform stands on ${(g :> string)}`)
    }
  )
  switch b {
  | Some(b) =>
    if a.version > b.version {
      path->Array.push(
        `${at}: the internal platform runs v${int(a.version)}, newer than the external's v${int(
            b.version,
          )}`,
      )
    }
    if b.version - a.version > Bootstrap.window {
      path->Array.push(
        `${at}: the external platform runs more than ${int(
            Bootstrap.window,
          )} ahead of the internal's pin`,
      )
    }
  | None => ()
  }
  let ran = steps->Array.slice(~start=0, ~end=i)
  switch before {
  | Some(before) =>
    if a.version != before.internal.version {
      if !(ran->Array.some(s => s.external_->Option.mapOr(false, e => e.version == a.version))) {
        path->Array.push(
          `${at}: the pin moves to v${int(a.version)}, which the external platform never ran`,
        )
      }
    }
    a.on->Array.forEach(f =>
      if (
        !ons(before.internal, f) &&
        !(ran->Array.some(s => s.external_->Option.mapOr(false, e => ons(e, f))))
      ) {
        path->Array.push(
          `${at}: the internal platform turns on ${(f :> string)}, never proven on the external`,
        )
      }
    )
  | None => ()
  }
  if step.users == Some(#invited) && !ons(a, #metering) {
    path->Array.push(`${at}: others invited before the internal platform meters its use`)
  }
  if before->Option.flatMap(b => b.users) == Some(#invited) && step.users != Some(#invited) {
    path->Array.push(`${at}: the invited sent away again`)
  }
  if before->Option.flatMap(b => b.internal.plan) == Some(#paid) && a.plan != Some(#paid) {
    path->Array.push(`${at}: the paid plan given up again`)
  }
  if step.cells != None && b == None {
    path->Array.push(`${at}: cells, with no external platform`)
  }
  if step.cells == Some(#"database organization") && !ons(a, #replicated) {
    path->Array.push(
      `${at}: a database organization without a replicated log, so every footing on it writes through one`,
    )
  }
})
if stops->Array.length > Bootstrap.stops {
  path->Array.push(
    `the bootstrap stops ${int(stops->Array.length)} times, more than ${int(Bootstrap.stops)}`,
  )
}
let kindsGiven = d =>
  Resources.extensionKinds(d)
  ->Map.keys
  ->Array.fromIterator
  ->Array.map(k => (k :> string))
  ->Array.toSorted(byText)
  ->Array.join(" ")
dimension(
  "Bootstrap path",
  "From day one by hand, does every step hold, and does each deployment reach it by a move it may take?",
  path,
  ~notes=[
    steps->Array.mapWithIndex((s, i) =>
      `${int(i)}: internal v${int(s.internal.version)}${s.internal.plan == Some(#paid)
          ? " paid"
          : ""}${switch s.external_ {
        | Some(e) => `, external v${int(e.version)}`
        | None => ""
        }}${switch s.cells {
        | Some(c) => `, cells ${(c :> string)}`
        | None => ""
        }} -- ${s.what}`
    ),
    steps->Array.mapWithIndex((s, i) =>
      `${int(i)}: extensions give, internal ${kindsGiven(s.internal)}${switch s.external_ {
        | Some(e) => `; external ${kindsGiven(e)}`
        | None => ""
        }}`
    ),
    [`planned stops: ${stops->orNone("; ")}`],
  ]->Array.flat,
  (),
)

// The footing, RFC b8f35: what it keeps must be bounded, and what each step asks of the vendor's
// plan is counted in rows a day, the load of an idle platform alone a violation past the plan.
let rows = Footing.rows
let assumed = Footing.assumed
let footing = []
Footing.kept
->Dict.toArray
->Array.forEach(((name, k)) =>
  if k.grows != #bounded && k.open_ == None {
    footing->Array.push(`${name} grows with ${(k.grows :> string)}: ${k.what}`)
  }
)
let round = x => num(Math.round(x))
let floor = x => num(Math.floor(x))
let load = steps->Array.mapWithIndex((step, i) => {
  let external_ = assumed.external_(i)
  let replicated = step.cells == Some(#"database organization") && ons(step.internal, #replicated)
  let organizations =
    assumed.internal +. (step.cells == Some(#"one each") ? external_ : replicated ? 1. : 0.)
  let own = organizations *. assumed.tablets *. rows.idleTablet
  // An external organization's footing is a database of its cell, so each of its writes is a commit
  // there, until a replicated log keeps it off the vendor's footing.
  let theirs = replicated ? 0. : external_ *. assumed.tablets *. rows.idleTablet *. rows.commit
  let idle = own +. theirs
  let plan = step.internal.plan->Option.getOr(#free)
  let allowed = Footing.allowed(plan)
  if idle > allowed {
    footing->Array.push(
      `step ${int(i)}: an idle platform writes ${round(
          idle,
        )} rows a day, past the ${(plan :> string)} plan's ${round(allowed)}`,
    )
  }
  let left = Math.max(allowed -. idle, 0.)
  `${int(i)}: idle ${round(idle)} of ${round(allowed)} rows a day (${round(
      idle /. allowed *. 100.,
    )}%); what is left holds ${floor(left /. rows.smallWrite)} small writes, or ${floor(
      left /. rows.commit,
    )} commits, or ${floor(left /. rows.largeMiB /. 1024.)} GiB written large`
})
dimension(
  "Footing",
  "Is what each footing keeps bounded, and does each step fit the rows a day its plan allows?",
  footing,
  ~notes=[
    Footing.kept
    ->Dict.toArray
    ->Array.map(((name, k)) =>
      `${name}: ${(k.grows :> string)}${switch k.bound {
        | Some(b) => `, by ${b}`
        | None => ""
        }} -- ${k.what}`
    ),
    [
      `assumed: ${num(assumed.tablets)} tablets an organization, each writing ${num(
          rows.idleTablet,
        )} rows a day idle, ${num(assumed.internal)} organizations of the internal platform's own`,
    ],
    load,
  ]->Array.flat,
  (),
)

// The contracts, RFC fhg6w: each declared once, in the subset, and written out as the product every
// language reads. A product changed in place, a type of a record whose version stayed, is refused.
let contractRules = []
let declared = Dict.fromArray(Contracts.types->Array.map(t => (t.name, t)))
let unique = (names, what) => {
  let seen = Set.make()
  names->Array.forEach(n => {
    if seen->Set.has(n) {
      contractRules->Array.push(`${what}: ${n} twice`)
    }
    seen->Set.add(n)
  })
}
unique(Contracts.types->Array.map(t => t.name), "a type")
let checkFields = (where, fields: array<Contracts.field>, ~content) => {
  unique(fields->Array.map(f => f.name), where)
  unique(fields->Array.map(f => int(f.key)), `${where}'s keys`)
  fields->Array.forEach(f => {
    if f.key < 1 {
      contractRules->Array.push(
        `${where}.${f.name}: key ${int(f.key)}, below 1, which is the case's or the description's`,
      )
    }
    if content && f.name == "description" {
      contractRules->Array.push(
        `${where}: declares description, which every record's content holds already`,
      )
    }
    Contracts.refers(f.shape)->Array.forEach(r =>
      switch r {
      | #type_(n) =>
        if declared->Dict.get(n) == None {
          contractRules->Array.push(`${where}.${f.name}: no type ${n}`)
        }
      | #id(k) =>
        if Graph.records->Dict.get(k) == None {
          contractRules->Array.push(`${where}.${f.name}: an id of ${k}, no kind of record`)
        }
      }
    )
  })
}
let isContent = n => Contracts.contents->Array.some(c => c.content == n)
Contracts.types->Array.forEach(t =>
  switch t.def {
  | Record(fields) => checkFields(t.name, fields, ~content=isContent(t.name))
  | Enum({choices, ordered}) =>
    unique(choices->Array.map(c => c.name), t.name)
    unique(choices->Array.map(c => int(c.code)), `${t.name}'s codes`)
    if ordered && choices->Array.some(c => c.code < 1) {
      contractRules->Array.push(`${t.name}: an ordered level coded below 1, 13ixj`)
    }
  | Union({cases}) =>
    unique(cases->Array.map(c => c.name), t.name)
    unique(cases->Array.map(c => int(c.code)), `${t.name}'s codes`)
    cases->Array.forEach(c => {
      if c.code < 1 {
        contractRules->Array.push(`${t.name}.${c.name}: coded below 1`)
      }
      checkFields(`${t.name}.${c.name}`, c.fields, ~content=false)
    })
  }
)
unique(Contracts.contents->Array.map(c => c.kind), "a record's content")
Contracts.contents->Array.forEach(c => {
  if Graph.records->Dict.get(c.kind) == None {
    contractRules->Array.push(`${c.kind}'s content: no such kind of record`)
  }
  switch declared->Dict.get(c.content) {
  | Some({def: Record(_)}) => ()
  | Some(_) => contractRules->Array.push(`${c.kind}'s content, ${c.content}, is no record`)
  | None => contractRules->Array.push(`${c.kind}'s content: no type ${c.content}`)
  }
})
let made = Contracts.product(
  ~half=k => Graph.records->Dict.get(k)->Option.mapOr("", r => (r.half :> string)),
  ~writes=k => Graph.records->Dict.get(k)->Option.mapOr([], r => r.writes),
)
let productUrl = url("contracts.json", importMetaUrl)
let kept = existsSync(productUrl) ? Some(JSON.parseOrThrow(readFileSync(productUrl))) : None
let text = (j: JSON.t) => JSON.stringify(j)
let member = (j: JSON.t, k) =>
  switch j {
  | Object(d) => d->Dict.get(k)
  | _ => None
  }
let items = (j: option<JSON.t>) =>
  switch j {
  | Some(Array(a)) => a
  | _ => []
  }
let named = (j: JSON.t, k) => j->member(k)->Option.flatMap(JSON.Decode.string)->Option.getOr("")
// The types a record's content reaches, by name, each with its definition.
let reach = (p: JSON.t, root) => {
  let defs = p->member("types")
  let found = Map.make()
  let rec walk = n =>
    if !(found->Map.has(n)) {
      switch defs->Option.flatMap(d => d->member(n)) {
      | Some(d) =>
        found->Map.set(n, d)
        let rec names = (s: JSON.t) =>
          switch (s->member("type"), s->member("list"), s->member("map")) {
          | (Some(String(t)), _, _) => [t]
          | (_, Some(inner), _) | (_, _, Some(inner)) => names(inner)
          | _ => []
          }
        let fields = Array.concat(
          items(d->member("record")),
          items(d->member("union")->Option.flatMap(u => u->member("cases")))->Array.flatMap(c =>
            items(c->member("fields"))
          ),
        )
        fields->Array.forEach(f => f->member("shape")->Option.mapOr([], names)->Array.forEach(walk))
      | None => ()
      }
    }
  walk(root)
  found
}
// What an old reader of a version can no longer read: a type it reached gone or changed, past a
// record's fields that are new and optional.
let breaks = (old: JSON.t, now: JSON.t) => {
  let found = []
  items(old->member("records"))->Array.forEach(r => {
    let kind = r->named("kind")
    switch items(now->member("records"))->Array.find(x => x->named("kind") == kind) {
    | Some(n)
      if text(n->member("version")->Option.getOr(Null)) ==
        text(r->member("version")->Option.getOr(Null)) =>
      let before = reach(old, r->named("content"))
      let after = reach(now, n->named("content"))
      before->Map.forEachWithKey((d, name) =>
        switch after->Map.get(name) {
        | None => found->Array.push(`${kind}: ${name} gone, its version kept`)
        | Some(a) =>
          switch (d->member("record"), a->member("record")) {
          | (Some(Array(was)), Some(Array(is))) =>
            was->Array.forEach(
              f =>
                if !(is->Array.some(g => text(g) == text(f))) {
                  found->Array.push(
                    `${kind}: ${name}.${f->named("name")} removed or changed, its version kept`,
                  )
                },
            )
            is->Array.forEach(
              g =>
                if (
                  !(was->Array.some(f => f->named("name") == g->named("name"))) &&
                  g->member("optional") == None
                ) {
                  found->Array.push(
                    `${kind}: ${name}.${g->named("name")} added and required, its version kept`,
                  )
                },
            )
          | _ =>
            if text(d) != text(a) {
              found->Array.push(`${kind}: ${name} changed, its version kept`)
            }
          }
        }
      )
    | _ => ()
    }
  })
  found
}
let write = args->Array.includes("--write")
switch kept {
| Some(k) if text(k) == text(made) => ()
| Some(k) if write =>
  switch breaks(k, made) {
  | [] => writeFileSync(productUrl, JSON.stringify(made, ~space=2) ++ "\n")
  | b => b->Array.forEach(x => contractRules->Array.push(`refused to write contracts.json: ${x}`))
  }
| None if write => writeFileSync(productUrl, JSON.stringify(made, ~space=2) ++ "\n")
| _ => contractRules->Array.push("contracts.json is not what the model writes; run with --write")
}
dimension(
  "Contracts",
  "Is every contract declared once in the subset, every name it uses resolved, and contracts.json what the model writes, never changed in place?",
  contractRules,
  ~notes=[
    `declared: ${Contracts.contents->Array.map(c => `${c.kind} v${int(c.version)}`)->orNone(", ")}`,
    `to declare: ${Graph.records
      ->Dict.keysToArray
      ->Array.filter(k => !(Contracts.contents->Array.some(c => c.kind == k)))
      ->orNone(", ")}`,
  ],
  (),
)

Console.log("\n# Boundaries, and whether each has its contract")
let needed: Map.t<string, array<string>> = Map.make()
designed->Array.forEach(((name, p)) =>
  p.edges->Array.forEach(edge =>
    if !known(edge.to_) {
      needed->Map.set(
        edge.to_,
        needed->Map.get(edge.to_)->Option.getOr([])->Array.concat([`${name} ${tag(edge)}`]),
      )
    }
  )
)
needed->Map.forEachWithKey((from, to_) => {
  let b = boundary(to_)
  Console.log(
    `  ${contracted(to_) ? "contract" : "none    "} ${to_->String.padEnd(
        14,
        " ",
      )} ${from->Array.join(", ")}`,
  )
  Console.log(
    `           kept by: ${switch b->Option.flatMap(b => b.keptBy) {
      | Some(k) =>
        `${k}${switch b->Option.flatMap(b => b.triage) {
          | Some(t) => ` [${(t :> string)}]`
          | None => ""
          }}`
      | None => "undecided"
      }}`,
  )
})
Graph.boundaries
->Dict.keysToArray
->Array.forEach(to_ =>
  if !(needed->Map.has(to_)) {
    Console.log(`  unused   ${to_}: no edge needs it`)
  }
)
needed
->Map.keys
->Array.fromIterator
->Array.forEach(to_ =>
  if boundary(to_) == None {
    Console.log(`  unlisted ${to_}: add it to boundaries`)
  }
)

// The completion rule of theory, `spec/process.md`: every boundary is kept by someone and sorted.
let unsorted =
  needed
  ->Map.keys
  ->Array.fromIterator
  ->Array.filter(to_ =>
    boundary(to_)->Option.flatMap(b => b.keptBy) == None ||
      boundary(to_)->Option.flatMap(b => b.triage) == None
  )
Console.log(
  `\n# Completion\n  ${unsorted->Array.length > 0
      ? `not yet kept and sorted: ${unsorted->Array.join(", ")}`
      : "every boundary is kept and sorted"}`,
)

// The checklist, `model/checklist.res`, grows by itself: every open question a draft lists and every
// open mark in the model names its row in brackets, `[B12]`, and one that names none is unfiled
// until it is, so a new structure's new questions reach the checklist without being copied there.
let hasTag = text => /\[([A-E]\d+)\]/->RegExp.test(text)
let tagsIn = text => {
  let re = /\[([A-E]\d+)\]/g
  let found = []
  let go = ref(true)
  while go.contents {
    switch re->RegExp.exec(text) {
    | Some(m) =>
      switch m->RegExp.Result.matches {
      | [Some(id)] => found->Array.push(id)
      | _ => ()
      }
    | None => go := false
    }
  }
  found
}
type mark = {where: string, mutable text: string}
let marks: array<mark> = []
let rfcs = url("../rfcs/", importMetaUrl)
readdirSync(rfcs)
->Array.filter(f => f->String.endsWith(".md"))
->Array.toSorted(byText)
->Array.forEach(file => {
  let text = readFileSync(urlIn(file, rfcs))
  let at = text->String.indexOf("Open, for the discussion that follows:")
  if at >= 0 {
    let id = switch /-([a-z0-9]{5})\.md$/->RegExp.exec(file) {
    | Some(m) =>
      switch m->RegExp.Result.matches {
      | [Some(id)] => id
      | _ => file
      }
    | None => file
    }
    let bullet = ref(None)
    let lines = text->String.slice(~start=at)->String.split("\n")->Array.slice(~start=1)
    let i = ref(0)
    while i.contents < lines->Array.length {
      let l = lines->Array.getUnsafe(i.contents)
      i := i.contents + 1
      if l->String.startsWith("- ") {
        let b = [l->String.slice(~start=2)]
        bullet := Some(b)
        marks->Array.push({where: id, text: b->Array.join(" ")})
      } else if l->String.startsWith("  ") && bullet.contents != None {
        switch bullet.contents {
        | Some(b) =>
          b->Array.push(l->String.trim)
          (marks->Array.getUnsafe(marks->Array.length - 1)).text = b->Array.join(" ")
        | None => ()
        }
      } else if l->String.trim == "" {
        bullet := None
      } else {
        i := lines->Array.length
      }
    }
  }
})
parts
->Dict.toArray
->Array.forEach(((name, p)) =>
  p.edges->Array.forEach(edge =>
    switch edge.open_ {
    | Some(o) => marks->Array.push({where: `${name} -> ${edge.to_}`, text: o})
    | None => ()
    }
  )
)
Graph.globalOpen->Array.forEach(g => marks->Array.push({where: "globalOpen", text: g}))
Footing.kept
->Dict.toArray
->Array.forEach(((name, k)) => {
  switch k.open_ {
  | Some(o) => marks->Array.push({where: `footing ${name}`, text: o})
  | None => ()
  }
  switch k.bound {
  | Some(b) if hasTag(b) => marks->Array.push({where: `footing ${name}`, text: b})
  | _ => ()
  }
})
let openWords = /\b(is|are) open\b|\bOpen:/
Graph.boundaries
->Dict.toArray
->Array.forEach(((name, b)) => {
  [b.contract, b.keptBy]->Array.forEach(t =>
    switch t {
    | Some(text) if openWords->RegExp.test(text) => marks->Array.push({where: name, text})
    | _ => ()
    }
  )
  if (
    b.triage == Some(#later) &&
      !([b.contract, b.keptBy]->Array.some(t => t->Option.mapOr(false, hasTag)))
  ) {
    marks->Array.push({where: name, text: `left for later: ${b.keptBy->Option.getOr("")}`})
  }
})

let checklist = Checklist.checklist
let rowsWrong = []
let ids = Set.make()
checklist->Array.forEach(item => {
  if ids->Set.has(item.id) {
    rowsWrong->Array.push(`${item.id}: listed twice`)
  }
  ids->Set.add(item.id)
  if !(item.id->String.startsWith((item.group :> string))) {
    rowsWrong->Array.push(`${item.id}: filed under ${(item.group :> string)}`)
  }
  if item.group == #C && item.step->Option.mapOr(true, s => steps[s] == None) {
    rowsWrong->Array.push(`${item.id}: names no step of the bootstrap path`)
  }
  if item.group != #C && item.step != None {
    rowsWrong->Array.push(`${item.id}: only a row of group C waits for a later step`)
  }
})
let unfiled = []
marks->Array.forEach(m => {
  let named = tagsIn(m.text)
  if named->Array.length == 0 {
    unfiled->Array.push(`unfiled, ${m.where}: ${m.text}`)
  }
  named->Array.forEach(id =>
    switch checklist->Array.find(x => x.id == id) {
    | None => rowsWrong->Array.push(`${m.where} names ${id}, no row of the checklist`)
    | Some({done: d}) =>
      rowsWrong->Array.push(`${m.where} still lists ${id} open, though it was decided in ${d}`)
    | Some(_) => ()
    }
  )
})

let readyArg = args->Array.find(a => a == "--ready" || a->String.startsWith("--ready="))
let ready = readyArg != None
let upTo = switch readyArg {
| Some(a) if a->String.includes("=") => number(a->String.split("=")->Array.getUnsafe(1))
| _ => 0.
}
if ready && (!isInteger(upTo) || steps[upTo->Float.toInt] == None) {
  rowsWrong->Array.push(`--ready=${num(upTo)} names no step of the bootstrap path`)
}
let open_ = checklist->Array.filter(x => x.done == None)
let blocking =
  open_->Array.filter(x =>
    x.group == #A ||
    x.group == #B ||
    x.group == #E ||
    (x.group == #C && x.step->Option.mapOr(false, s => Int.toFloat(s) <= upTo))
  )
dimension(
  "Checklist",
  ready
    ? `Is every row that blocks step ${num(
          upTo,
        )} crossed off, and every open question filed, so it may begin?`
    : "Is every row well formed, and every open question filed? Run with --ready to ask whether building may begin.",
  [
    rowsWrong,
    unfiled,
    ready ? blocking->Array.map(x => `open ${x.id}: ${x.what} (${x.from})`) : [],
  ]->Array.flat,
  ~notes=[
    [
      `open: ${([#A, #B, #C, #D, #E]: array<Checklist.group>)
        ->Array.map(g =>
          `${(g :> string)} ${int(open_->Array.filter(x => x.group == g)->Array.length)}`
        )
        ->Array.join(", ")}; crossed off: ${int(
          checklist->Array.length - open_->Array.length,
        )}; open questions filed: ${int(marks->Array.length - unfiled->Array.length)} of ${int(
          marks->Array.length,
        )}`,
      `blocking step ${num(upTo)}: ${blocking->Array.length > 0
          ? blocking->Array.map(x => x.id)->Array.join(" ")
          : "none, it may begin"}`,
    ],
    ready
      ? open_
        ->Array.filter(x => !(blocking->Array.includes(x)))
        ->Array.map(x =>
          `later ${x.id}${switch x.step {
            | Some(s) => ` (before step ${int(s)})`
            | None => ""
            }}: ${x.what}`
        )
      : [],
  ]->Array.flat,
  (),
)

if args->Array.includes("--s1") {
  Console.log("\n# D4 Recovery (s1): lose one running part, and what stops by hard serve edges")
  designed->Array.forEach(((lost, _)) => {
    let down = Set.fromArray([lost])
    let grew = ref(true)
    while grew.contents {
      grew := false
      designed->Array.forEach(((n, p)) =>
        if (
          !(down->Set.has(n)) &&
          p.edges->Array.some(x => x.hard && serve(x) && down->Set.has(x.to_))
        ) {
          down->Set.add(n)
          grew := true
        }
      )
    }
    down->Set.delete(lost)->ignore
    let rest = down->Set.values->Array.fromIterator
    Console.log(
      `  ${lost->String.padEnd(9, " ")} -> ${rest->Array.length > 0
          ? rest->Array.join(", ")
          : "nothing"}`,
    )
  })
}
process->setExitCode(failed.contents ? 1 : 0)
