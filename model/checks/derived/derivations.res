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
        switch Realized.providers(n) {
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
              !(Realized.provides(main)->Array.includes(c.from)) ||
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

/** Every violation on the as-built graph, by the dimension finding it, RFC s42ex. */
let scaffolds = [
  ("Rules", Rules.check(Realized.graph)),
  ("Roles", Roles.check(Realized.graph)),
  ("Crossing", Crossing.check(Realized.graph)),
]->Array.flatMap(((title, c)) => c.violations->Array.map(v => (title, v)))

let violating = Set.fromArray(scaffolds->Array.flatMap(((_, v)) => v.at))

/** Whether a name counts as provided where an edge points to it, a violating provider too. */
let counted = n => Realized.providers(n) != [] || trusted(n) || isRole(n) || Components.elsewhere(n)

let frontier = () => {
  let candidates =
    held->Array.filter(n =>
      !trusted(n) && !Components.elsewhere(n) && !(isRole(n) && Realized.providers(n) == [])
    )
  let unrightly =
    candidates->Array.filter(n =>
      !(Realized.providers(n)->Array.some(m => !(violating->Set.has(m))))
    )
  let waitsOn = n => edgesOf(n)->Array.filter(x => x.hard && !counted(x.to_))->Array.map(x => x.to_)
  let (open_, waiting) =
    unrightly->Array.reduce(([], []), ((o, w), n) =>
      waitsOn(n) == [] ? (o->Array.concat([n]), w) : (o, w->Array.concat([n]))
    )
  report(
    "Frontier",
    "Which names are not yet rightly provided, yet every name their hard edges point to is? Derived, never refused.",
    Array.concat(
      open_->Array.map(n =>
        switch Realized.providers(n) {
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

let run = () => {
  provided()
  sampled()
  frontier()
  buildable()
  report(
    "Scaffolds",
    "Which rules does the as-built graph break, run as on the design? Reported, never refused, until the platform keeps data.",
    scaffolds->Array.map(((title, v)) => `${title}: ${v.text}`),
  )
}
