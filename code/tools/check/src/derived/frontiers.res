open Base
open Provisions

/** Every violation on an as-built graph, by the dimension finding it, RFC s42ex. */
let scaffoldsOf = g =>
  [
    ("Rules", Rules.check(g).violations),
    ("Roles", Roles.check(g).violations),
    ("Crossing", Crossing.check(g).violations),
    ("D1 Bootstrap", Dimensions.bootstrap(g).violations),
    ("D2 Restart", Dimensions.restart(g).violations),
    ("D3 Upgrade", Dimensions.upgrade(g).violations),
  ]->Array.flatMap(((title, found)) => found->Array.map(v => (title, v)))

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
