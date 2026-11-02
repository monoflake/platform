open Base
open Provisions
open Frontiers
open Downward

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
      | Vendor(_) | Workload(_) | Beneath(_) | Import(_) => []
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
