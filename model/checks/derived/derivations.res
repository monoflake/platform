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
  /** Whether a name is filled through a `Beneath` that check one or two finds wrong, btzlt. */
  wrongBelow: string => bool,
}

let everything = {
  title: "",
  running: Realized.built,
  scaffolds: scaffoldsOf(Realized.graph),
  apart: _ => false,
  elsewhere: Components.elsewhere,
  wrongBelow: _ => false,
}

/** Whether a name counts as provided where an edge points to it, a violating provider too. */
let counted = (v: view, n) =>
  Realized.providers(v.running, n) != [] || trusted(n) || isRole(n) || v.apart(n) || v.elsewhere(n)

/** The Frontier's lines over one view, each name not yet rightly provided, then those waiting. */
let frontierLines = (v: view) => {
  let providers = n => Realized.providers(v.running, n)
  let violating = Set.fromArray(v.scaffolds->Array.flatMap(((_, f)) => f.at))
  let candidates =
    held->Array.filter(n =>
      !trusted(n) && !v.elsewhere(n) && !v.apart(n) && !(isRole(n) && providers(n) == [])
    )
  let violates = (n, m) => violating->Set.has(m) || (m == Realized.beneath && v.wrongBelow(n))
  let unrightly = candidates->Array.filter(n => !(providers(n)->Array.some(m => !violates(n, m))))
  let waitsOn = n =>
    edgesOf(n)->Array.filter(x => x.hard && !counted(v, x.to_))->Array.map(x => x.to_)
  let (open_, waiting) =
    unrightly->Array.reduce(([], []), ((o, w), n) =>
      waitsOn(n) == [] ? (o->Array.concat([n]), w) : (o, w->Array.concat([n]))
    )
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
  )
}

let frontier = (v: view) =>
  report(
    `Frontier${v.title}`,
    "Which names are not yet rightly provided, yet every name their hard edges point to is? Derived, never refused.",
    frontierLines(v),
  )

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

/**
 * Whether `name` is a product at layer 0 the platform beneath answers, by its own name or any of
 * its answers, RFC 94y0d's way down.
 */
let throughProduct = (~lookup=component, name) => {
  let products = Provided.beneath.answers->Option.getOr([])
  lookup(name)->Option.mapOr(false, (c: Components.component) =>
    c.layer == 0 &&
      (products->Array.includes(name) ||
        c.answers->Option.getOr([])->Array.some(a => products->Array.includes(a)))
  )
}

/** The contracts the filled name answers that the name taken from beneath does not, btzlt. */
let unanswered = (~lookup=component, filled, taken) => {
  let answers = n => lookup(n)->Option.flatMap(c => c.answers)->Option.getOr([])
  filled == taken ? [] : answers(filled)->Array.filter(c => !(answers(taken)->Array.includes(c)))
}

/** Each name a column takes down through anything but a product at layer 0, RFC btzlt. */
let downward = (~lookup=component, column, d: Provided.deployed) =>
  Realized.filledBeneath(d)
  ->Array.filter(b => !throughProduct(~lookup, b.name))
  ->Array.map(b => (
    "Beneath",
    foundAt(
      [b.filled],
      `${column} fills ${b.filled} by ${b.name} in ${b.deployment}, no product at layer 0 beneath answers, against RFC 94y0d`,
    ),
  ))

/**
 * Whether a name is provided in a deployment, by a fill there or a block there declaring it, an
 * unbuilt block too, since its own column reports it.
 */
let providedThere = (~declared=Provided.all, d: Provided.deployed, name) =>
  d.fills->Array.some(((n, _)) => n == name) ||
    Realized.blocksIn(d)->Array.some(m =>
      Realized.provides({mains: [], declared}, m)->Array.includes(name)
    )

/** Where a chain of `Beneath` from a name ends, each deployment it passes named. */
type ending =
  | Reached
  | NotThere(string, string)
  | NoDeployment(string)
  | Back(string)

/** A chain of `Beneath` followed from `name` in `deployment` to its end, btzlt. */
let rec followed = (~deployments: dict<Provided.deployed>, passed, deployment, name) =>
  if passed->Array.includes(deployment) {
    Back(deployment)
  } else {
    switch deployments->Dict.get(deployment) {
    | None => NoDeployment(deployment)
    | Some(there) =>
      switch there.fills->Array.find(((n, _)) => n == name) {
      | Some((_, Beneath({deployment: next, name: taken}))) =>
        followed(~deployments, passed->Array.concat([deployment]), next, taken)
      | Some((_, Block(_) | Vendor(_) | Workload(_))) => Reached
      | None => providedThere(there, name) ? Reached : NotThere(deployment, name)
      }
    }
  }

/** The deployments a column stands on, each a `Beneath` of it names, its own aside. */
let standsOn = (column, d: Provided.deployed) =>
  Realized.union([Realized.filledBeneath(d)->Array.map(b => b.deployment)])->Array.filter(n =>
    n != column
  )

/** A chain of deployments a column stands on that comes back to one already passed, if any. */
let circling = (~deployments: dict<Provided.deployed>, column, d) => {
  let rec walk = (path, at, d) =>
    standsOn(at, d)->Array.reduce(None, (found, next) =>
      switch found {
      | Some(_) => found
      | None if path->Array.includes(next) => Some(path->Array.concat([next]))
      | None =>
        deployments
        ->Dict.get(next)
        ->Option.flatMap(there => walk(path->Array.concat([next]), next, there))
      }
    )
  walk([column], column, d)
}

/**
 * What a column's `Beneath` fills mistake, btzlt, each at the names it fills: one deployment
 * beneath, never its own, a chain of them followed to a name provided, never coming back, and
 * every contract the filled name answers answered by the name taken.
 */
let mistakenBeneath = (
  ~deployments=Provided.deployments,
  ~lookup=component,
  column,
  d: Provided.deployed,
) => {
  let fills = Realized.filledBeneath(d)
  let all = fills->Array.map(b => b.filled)
  let named = Realized.union([fills->Array.map(b => b.deployment)])
  let circled = circling(~deployments, column, d)
  Array.concatMany(
    named->Array.length > 1
      ? [
          foundAt(
            all,
            `${column} stands on ${named->Array.join(", ")}, more than one deployment beneath`,
          ),
        ]
      : [],
    [
      circled->Option.mapOr([], chain => {
        let passed = chain->Array.join(" -> ")
        [
          foundAt(
            all,
            `${column} stands on a chain of deployments coming back to one passed, ${passed}`,
          ),
        ]
      }),
      fills->Array.flatMap(b => {
        let by = `${b.filled} is filled by ${b.name} in ${b.deployment}`
        let texts = if b.deployment == column {
          [`${b.filled} is filled from beneath by ${column}, the deployment's own`]
        } else {
          switch followed(~deployments, [column], b.deployment, b.name) {
          | Reached => []
          | NoDeployment(there) if there == b.deployment => [
              `${b.filled} is filled from beneath by ${there}, which is no deployment`,
            ]
          | NoDeployment(there) => [`${by}, a chain reaching ${there}, which is no deployment`]
          | NotThere(there, _) if there == b.deployment => [`${by}, which provides it not there`]
          | NotThere(there, n) => [
              `${by}, a chain ending at ${n} in ${there}, which provides it not there`,
            ]
          | Back(_) if circled != None => []
          | Back(there) => [`${by}, a chain coming back to ${there}, already passed`]
          }
        }
        let missing = unanswered(~lookup, b.filled, b.name)
        let unmet =
          missing == [] ? [] : [`${by}, which leaves ${missing->Array.join(", ")} unanswered`]
        Array.concat(texts, unmet)->Array.map(t => foundAt([b.filled], t))
      }),
    ],
  )
}

/** One deployment's as-built graph as the frontier reads it, RFC vgvx6. */
let viewOf = (~deployments=Provided.deployments, name, d: Provided.deployed) => {
  let running = Realized.runningIn(d)
  let apart = Realized.filledApart(d)->Array.map(((n, _)) => n)
  let below = downward(name, d)
  let wrong =
    Array.concat(
      below->Array.map(((_, f)) => f),
      mistakenBeneath(~deployments, name, d),
    )->Array.flatMap(f => f.at)
  {
    title: ` in ${name}`,
    running,
    scaffolds: Array.concat(scaffoldsOf(Realized.graphOf(running)), below),
    apart: n => apart->Array.includes(n),
    elsewhere: _ => false,
    wrongBelow: n => wrong->Array.includes(n),
  }
}

/** Which blocks and what else fill each name in one deployment, and what its fills mistake. */
let providedLines = (~deployments=Provided.deployments, column, v: view, d: Provided.deployed) => {
  let apart = Realized.filledApart(d)
  let below = Realized.filledBeneath(d)
  let fromBeneath = n =>
    below
    ->Array.filter(b => b.filled == n)
    ->Array.map(b => `${Realized.beneath}, ${b.name} in ${b.deployment}`)
  let names =
    held
    ->Array.filter(n => !trusted(n) || d.fills->Array.some(((m, _)) => m == n))
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
  Array.concatMany(
    names,
    [mistaken, mistakenBeneath(~deployments, column, d)->Array.map(f => f.text)],
  )
}

let providedIn = (column, v: view, d: Provided.deployed) =>
  report(
    `Provided${v.title}`,
    "Which blocks, vendors' resources, workloads or the platform beneath fill each name the design holds in this deployment? Derived, never refused.",
    providedLines(column, v, d),
  )

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
