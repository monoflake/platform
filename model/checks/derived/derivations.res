/**
 * What is derived of what is built against what is designed, never refused, RFC s42ex. A name
 * answers its own `answers` and each contract on an edge to it or one whose `reads` names it.
 */
open Base

/** Every name the design graph holds, its components and roles, then its boundaries. */
let held = Array.concat(
  components->Dict.keysToArray->Array.toSorted(byText),
  Boundaries.boundaries->Dict.keysToArray->Array.toSorted(byText),
)

/** The ground and the operator, outside the design and trusted as written. */
let trusted = n =>
  switch component(n)->Option.flatMap(p => p.kind) {
  | Some(#ground | #operator) => true
  | Some(#provided) | None => false
  }

let isRole = n => component(n)->Option.flatMap(p => p.kind) == Some(#provided)

/** Each contract a name answers, with the source and the half it is asked across. */
let asked = n => {
  let answering =
    component(n)
    ->Option.flatMap(p => p.answers)
    ->Option.getOr([])
    ->Array.map(c => (n, component(n)->Option.flatMap(p => p.half), c))
  let pointing = designed->Array.flatMap(((from, p)) =>
    p.edges
    ->Array.filter(x =>
      switch x.reads {
      | Some(names) if names != [] => names->Array.includes(n)
      | _ => x.to_ == n
      }
    )
    ->Array.flatMap(x =>
      x.contract
      ->Option.getOr([])
      ->Array.map(c => (from, Crossing.halfAcross(design, p.half, x.to_), c))
    )
  )
  Array.concat(answering, pointing)
}

let contractsOf = n => Realized.union([asked(n)->Array.map(((_, _, c)) => c)])

/** How many cases each interface has in `tests/`, its interface the contract of its name. */
let cases: dict<int> = {
  let counted = Dict.make()
  Array.concatMany(
    Cases.files("tests/kinds"),
    [Cases.files("tests/products"), Cases.files("tests/components")],
  )->Array.forEach(path => {
    let j = Cases.read(path)
    text(j->member("interface"))->Option.forEach(i =>
      counted->Dict.set(
        i,
        counted->Dict.get(i)->Option.getOr(0) + Cases.items(j->member("cases"))->Array.length,
      )
    )
  })
  counted
}

/** A name's samples, each interface it answers with its count of cases. */
let samplesOf = n =>
  contractsOf(n)->Array.filterMap(c => cases->Dict.get(c)->Option.map(count => (c, count)))

let totalOf = n => samplesOf(n)->Array.reduce(0, (sum, (_, count)) => sum + count)

/** The contracts a name is asked that are not declared, each one led by `?` among them. */
let undeclaredOf = n =>
  Realized.union([
    asked(n)->Array.filterMap(((from, half, c)) =>
      c->String.startsWith("?") || Crossing.fault(design, from, half, c) != None ? Some(c) : None
    ),
  ])

let provided = () =>
  report(
    "Provided",
    "Which blocks provide each name the design holds? Derived, never refused.",
    Array.concat(
      held
      ->Array.filter(n => !trusted(n))
      ->Array.map(n =>
        switch Realized.providers(Realized.built, n) {
        | [] if Components.elsewhere(n) => `${n}: another repository's`
        | [] if isRole(n) => `${n}: none, a role not yet filled`
        | [] => `${n}: none`
        | by => `${n}: ${by->Array.join(", ")}`
        }
      ),
      Provided.all
      ->Dict.toArray
      ->Array.flatMap(((main, b)) =>
        Array.concat(
          Realized.mains->Array.includes(main)
            ? []
            : [`${main}: declared, yet no block whose code is written`],
          b.provides
          ->Array.filter(n => !(held->Array.includes(n)))
          ->Array.map(n => `${main} provides ${n}, which the design holds not`)
          ->Array.concat(
            b.carries
            ->Option.getOr([])
            ->Array.filter(c =>
              !(Realized.provides(Realized.built, main)->Array.includes(c.from)) ||
              !(edgesOf(c.from)->Array.some(x => x.to_ == c.to_))
            )
            ->Array.map(c =>
              `${main} carries ${c.from} -> ${c.to_}, which it provides not or the design holds not`
            ),
          ),
        )
      ),
    ),
  )

let sampled = () => {
  let reached = held->Array.flatMap(contractsOf)
  report(
    "Sampled",
    "How many samples has each component, each case by its interface, the contract of its name, and the components answering it? Derived, never refused.",
    Array.concat(
      components
      ->Dict.keysToArray
      ->Array.toSorted(byText)
      ->Array.filter(n => !trusted(n))
      ->Array.map(n =>
        switch samplesOf(n) {
        | [] => `${n}: no samples`
        | by =>
          `${n}: ${int(totalOf(n))}, ${by
            ->Array.map(((c, count)) => `${c} ${int(count)}`)
            ->Array.join(", ")}`
        }
      ),
      [
        `reaching no name: ${cases
          ->Dict.toArray
          ->Array.filter(((i, _)) => !(reached->Array.includes(i)))
          ->Array.toSorted(((a, _), (b, _)) => byText(a, b))
          ->Array.map(((i, count)) => `${i} ${int(count)}`)
          ->orNone(", ")}`,
      ],
    ),
  )
}

/** Every violation on an as-built graph, by the dimension finding it, RFC s42ex. */
let scaffoldsOf = g =>
  [
    ("Rules", Rules.check(g)),
    ("Roles", Roles.check(g)),
    ("Crossing", Crossing.check(g)),
  ]->Array.flatMap(((title, c)) => c.violations->Array.map(v => (title, v)))

/**
 * One as-built graph as the frontier reads it, the blocks running, the names provided apart from
 * them and the names left to another repository, and the title its sections carry.
 */
type view = {
  title: string,
  running: Realized.running,
  scaffolds: array<(string, finding)>,
  apart: string => bool,
  elsewhere: string => bool,
}

let everything = {
  title: "",
  running: Realized.built,
  scaffolds: scaffoldsOf(Realized.graph),
  apart: _ => false,
  elsewhere: Components.elsewhere,
}

/** Whether a name counts as provided where an edge points to it, a violating provider too. */
let counted = (v: view, n) =>
  Realized.providers(v.running, n) != [] || trusted(n) || isRole(n) || v.apart(n) || v.elsewhere(n)

let frontier = (v: view) => {
  let providers = n => Realized.providers(v.running, n)
  let violating = Set.fromArray(v.scaffolds->Array.flatMap(((_, f)) => f.at))
  let candidates =
    held->Array.filter(n =>
      !trusted(n) && !v.elsewhere(n) && !v.apart(n) && !(isRole(n) && providers(n) == [])
    )
  let unrightly =
    candidates->Array.filter(n => !(providers(n)->Array.some(m => !(violating->Set.has(m)))))
  let waitsOn = n =>
    edgesOf(n)->Array.filter(x => x.hard && !counted(v, x.to_))->Array.map(x => x.to_)
  let (open_, waiting) =
    unrightly->Array.reduce(([], []), ((o, w), n) =>
      waitsOn(n) == [] ? (o->Array.concat([n]), w) : (o, w->Array.concat([n]))
    )
  report(
    `Frontier${v.title}`,
    "Which names are not yet rightly provided, yet every name their hard edges point to is? Derived, never refused.",
    Array.concat(
      open_->Array.map(n =>
        switch providers(n) {
        | [] => `${n}: no provider`
        | by => `${n}: ${by->Array.join(", ")}, each violating a rule as built`
        }
      ),
      [
        `waiting: ${waiting
          ->Array.map(n => `${n} on ${Realized.union([waitsOn(n)])->Array.join(", ")}`)
          ->orNone("; ")}`,
      ],
    ),
  )
}

let buildable = () => {
  let names = held->Array.filter(n => !trusted(n))
  let (ready, unready) = names->Array.reduce(([], []), ((r, w), n) =>
    switch (undeclaredOf(n), totalOf(n)) {
    | ([], count) if count > 0 => (r->Array.concat([`${n}: ${int(count)} samples`]), w)
    | ([], _) => (r, w->Array.concat([`${n} has no samples`]))
    | (undeclared, _) => (r, w->Array.concat([`${n} is asked ${undeclared->Array.join(", ")}`]))
    }
  )
  report(
    "Buildable",
    "Which names have every contract they answer and every one on an edge to them declared, and have samples? Derived, never refused.",
    Array.concat(ready, [`not yet: ${unready->orNone("; ")}`]),
  )
}

let scaffolds = (v: view) =>
  report(
    `Scaffolds${v.title}`,
    "Which rules does the as-built graph break, run as on the design? Reported, never refused, until the platform keeps data.",
    v.scaffolds->Array.map(((title, f)) => `${title}: ${f.text}`),
  )

/** Whether `name` is a product at layer 0 the platform beneath answers, RFC 94y0d's way down. */
let throughProduct = name =>
  Provided.beneath.answers->Option.getOr([])->Array.includes(name) &&
    component(name)->Option.mapOr(false, c => c.layer == 0)

/** Each name a column takes down through anything but a product at layer 0, RFC btzlt. */
let downward = (column, d: Provided.deployed) =>
  Realized.filledBeneath(d)
  ->Array.filter(b => !throughProduct(b.name))
  ->Array.map(b => (
    "Beneath",
    foundAt(
      [b.filled],
      `${column} fills ${b.filled} by ${b.name} in ${b.deployment}, no product at layer 0 beneath answers, against RFC 94y0d`,
    ),
  ))

/** One deployment's as-built graph as the frontier reads it, RFC vgvx6. */
let viewOf = (name, d: Provided.deployed) => {
  let running = Realized.runningIn(d)
  let apart = Realized.filledApart(d)->Array.map(((n, _)) => n)
  {
    title: ` in ${name}`,
    running,
    scaffolds: Array.concat(scaffoldsOf(Realized.graphOf(running)), downward(name, d)),
    apart: n => apart->Array.includes(n),
    elsewhere: _ => false,
  }
}

/** Whether a name is provided in a deployment, by a block providing it there or a fill there. */
let providedThere = (d: Provided.deployed, name) =>
  d.fills->Array.some(((n, _)) => n == name) ||
    Realized.providers(Realized.runningIn(d), name) != []

/** What a column's `Beneath` fills mistake, one deployment beneath and never its own, btzlt. */
let mistakenBeneath = (~deployments=Provided.deployments, column, d: Provided.deployed) => {
  let fills = Realized.filledBeneath(d)
  let named = Realized.union([fills->Array.map(b => b.deployment)])
  Array.concat(
    named->Array.length > 1
      ? [`${column} stands on ${named->Array.join(", ")}, more than one deployment beneath`]
      : [],
    fills->Array.flatMap(b =>
      switch deployments->Dict.get(b.deployment) {
      | _ if b.deployment == column => [
          `${b.filled} is filled from beneath by ${column}, the deployment's own`,
        ]
      | None => [`${b.filled} is filled from beneath by ${b.deployment}, which is no deployment`]
      | Some(there) if !providedThere(there, b.name) => [
          `${b.filled} is filled by ${b.name} in ${b.deployment}, which provides it not there`,
        ]
      | Some(_) => []
      }
    ),
  )
}

/** Which blocks and what else fill each name in one deployment, and what its fills mistake. */
let providedIn = (column, v: view, d: Provided.deployed) => {
  let apart = Realized.filledApart(d)
  let below = Realized.filledBeneath(d)
  let fromBeneath = n =>
    below
    ->Array.filter(b => b.filled == n)
    ->Array.map(b => `${Realized.beneath}, ${b.name} in ${b.deployment}`)
  let names =
    held
    ->Array.filter(n => !trusted(n) || below->Array.some(b => b.filled == n))
    ->Array.map(n => {
      let by = Array.concatMany(
        Realized.providers(v.running, n)->Array.filter(m => m != Realized.beneath),
        [fromBeneath(n), apart->Array.filter(((m, _)) => m == n)->Array.map(((_, what)) => what)],
      )
      by == [] ? `${n}: none` : `${n}: ${by->Array.join(", ")}`
    })
  let mistaken = d.fills->Array.flatMap(((n, f)) =>
    Array.concat(
      held->Array.includes(n) ? [] : [`${n} is filled, which the design holds not`],
      switch f {
      | Block(main) if component(main)->Option.isNone => [
          `${n} is filled by ${main}, which the design names not`,
        ]
      | Block(main) =>
        Array.concat(
          Realized.mains->Array.includes(main)
            ? []
            : [`${n} is filled by ${main}, yet no block whose code is written`],
          Realized.provides(v.running, main)->Array.includes(n)
            ? []
            : [`${n} is filled by ${main}, which declares providing it not`],
        )
      | Vendor(_) | Workload(_) | Beneath(_) => []
      },
    )
  )
  report(
    `Provided${v.title}`,
    "Which blocks, vendors' resources, workloads or the platform beneath fill each name the design holds in this deployment? Derived, never refused.",
    Array.concatMany(names, [mistaken, mistakenBeneath(column, d)]),
  )
}

/** Each target's snapshot, each contract's state by RFC s42ex's table, never refused. */
let statesIn = (v: view, d: Provided.deployed) =>
  report(
    `States${v.title}`,
    "What state does each contract's snapshot show on each target bound to this deployment? Read from the snapshots, bound where the driver reports its revision, never refused.",
    d.targets == []
      ? ["no target bound"]
      : d.targets->Array.flatMap(t => Measured.lines(t, Measured.read(t))),
  )

let deployment = (name, d: Provided.deployed) => {
  let v = viewOf(name, d)
  if d.fills == [] {
    ["Provided", "Frontier", "Scaffolds"]->Array.forEach(title =>
      report(`${title}${v.title}`, "Derived, never refused.", [`nothing filled in ${name}`])
    )
  } else {
    providedIn(name, v, d)
    frontier(v)
    scaffolds(v)
  }
  statesIn(v, d)
}

let run = () => {
  provided()
  sampled()
  frontier(everything)
  buildable()
  scaffolds(everything)
  Provided.deployments
  ->Dict.toArray
  ->Array.toSorted(((a, _), (b, _)) => byText(a, b))
  ->Array.forEach(((name, d)) => deployment(name, d))
}
