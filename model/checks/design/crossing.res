/**
 * Each edge between two of the platform's processes names the contract it carries, one the model
 * declares, an app's WIT or one in `undeclared`, and its target answers it. RFC fhg6w.
 */
open Base

let interfaces = Contracts.interfaces->Array.map(i => i.name)
let signed = Signed.signed->Array.map(r => r.name)
let sections = Signed.sections->Array.map(((n, _)) => `bundle.${n}`)
let pending = Components.undeclared->Array.map(((n, _)) => `?${n}`)

/**
 * Why a contract an edge from `name` names is none the model declares, given the half its records
 * are of, or none. One led by `?` is asked of `pending` and of the boundaries with a contract.
 */
let fault = (g: graph, name, half, c) =>
  if c->String.startsWith("record.") {
    let kind = c->String.slice(~start=String.length("record."))
    switch half {
    | Some(h) if g.records->Array.some(r => r.half == h && r.kind == kind) => None
    | _ => Some(`${c}, no record kind of its half`)
    }
  } else if c == "records" {
    g.records->Array.some(r => Some(r.half) == half && r.writes->Array.includes(name))
      ? None
      : Some(`records, yet ${name} writes none there`)
  } else if c->String.startsWith("?") {
    pending->Array.includes(c) || contracted(c)
      ? None
      : Some(`${c}, undeclared and named in no row`)
  } else if (
    c == "wit" ||
    interfaces->Array.includes(c) ||
    signed->Array.includes(c) ||
    sections->Array.includes(c)
  ) {
    None
  } else {
    Some(`${c}, no contract the model declares`)
  }

/** The half an edge's records are of, a footing's its own and any other edge's the source's. */
let halfAcross = (g: graph, half, to_) =>
  componentIn(g, to_)->Option.flatMap(t => t.half)->Option.orElse(half)

/** A name's base, its qualifier in parentheses aside, `footing` of `footing(organization)`. */
let base = n => n->String.split("(")->Array.get(0)->Option.getOr(n)

/** The whole a contract is a part of, `records` of `record.writer`, or the contract itself. */
let whole = c =>
  if c->String.startsWith("record.") {
    "records"
  } else if c->String.startsWith("bundle.") {
    "bundle"
  } else {
    c
  }

/**
 * Whether `to_` answers `c`, as its `answers` lists it, it is the base name of `to_`, or it is a
 * part of a whole `to_` answers.
 */
let answered = (g: graph, to_, c) =>
  switch componentIn(g, to_) {
  | None => true
  | Some(t) =>
    let listed = n => t.answers->Option.getOr([])->Array.includes(n) || n == base(to_)
    listed(c) || listed(whole(c))
  }

/**
 * Every edge over one graph that names no contract the model declares, or one its target does not
 * answer and no `reads` places elsewhere, RFC s42ex.
 */
let check = (g: graph): checked => {
  let found = []
  let used = Set.make()
  let named = ref(0)
  let nodes = designedIn(g)
  nodes->Array.forEach(((name, p)) =>
    p.edges->Array.forEach(x =>
      if x.replaces != Some(true) && known(x.to_) && x.to_ != "vendor" {
        let across = `${name} -> ${x.to_}`
        switch x.contract {
        | None | Some([]) =>
          found->Array.push(foundAt([name], `${across}: names no contract, ${x.why}`))
        | Some(cs) =>
          named := named.contents + 1
          cs->Array.forEach(
            c => {
              if c->String.startsWith("?") {
                used->Set.add(c)
              }
              switch fault(g, name, halfAcross(g, p.half, x.to_), c) {
              | Some(why) => found->Array.push(foundAt([name], `${across}: ${why}`))
              | None =>
                // An edge with `reads` has those it lists answer the contract, not its target.
                switch x.reads->Option.getOr([]) {
                | [] =>
                  if known(c) && !answered(g, x.to_, c) {
                    found->Array.push(
                      foundAt([name], `${across}: ${c}, which ${x.to_} does not answer`),
                    )
                  }
                | readers =>
                  readers->Array.forEach(
                    r =>
                      if component(r) == None {
                        found->Array.push(foundAt([name], `${across}: reads ${r}, no component`))
                      } else if known(c) && !answered(g, r, c) {
                        found->Array.push(
                          foundAt([name], `${across}: ${c}, which ${r} it reads does not answer`),
                        )
                      },
                  )
                }
              }
            },
          )
        }
      }
    )
  )
  pending->Array.forEach(c =>
    if !(used->Set.has(c)) {
      found->Array.push(foundAt([], `${c}: undeclared, yet no edge names it`))
    }
  )
  pending->Array.forEach(c =>
    if interfaces->Array.includes(c->String.slice(~start=1)) {
      found->Array.push(foundAt([], `${c}: marked undeclared, yet declared`))
    }
  )
  // Each driver giving a kind of compute is reached at deployment through `deployments`, by what
  // places it, vr5lw, v7v3w.
  Drivers.asked->Dict.forEachWithKey((d, driver) =>
    if (
      d.kinds->Array.some(k => [#function, #instance, #container]->Array.includes(k.kind)) &&
        !(
          nodes->Array.some(((_, p)) =>
            p.edges->Array.some(
              x =>
                x.to_ == driver &&
                x.when_ == #deploy &&
                x.contract->Option.getOr([])->Array.includes("deployments"),
            )
          )
        )
    ) {
      found->Array.push(
        foundAt(
          [driver],
          `${driver}: gives compute, yet nothing deploys onto it through deployments`,
        ),
      )
    }
  )
  {
    violations: found,
    notes: [`edges naming one: ${int(named.contents)}; undeclared: ${pending->orNone(", ")}`],
  }
}

let run = () => {
  let {violations, notes} = check(design)
  dimension(
    "Crossing",
    "Does every edge between two of the platform's processes name the contract it carries, declared or filed, and one its target answers?",
    violations->Array.map(v => v.text),
    ~notes,
    (),
  )
}
