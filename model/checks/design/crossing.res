/**
 * Each edge between two of the platform's processes names the contract it carries, one the model
 * declares, an app's WIT or one in `undeclared`. RFC fhg6w.
 */
open Base

let interfaces = Contracts.interfaces->Array.map(i => i.name)
let signed = Signed.signed->Array.map(r => r.name)
let sections = Signed.sections->Array.map(((n, _)) => `bundle.${n}`)
let pending = Components.undeclared->Array.map(((n, _)) => `?${n}`)

/**
 * Why a contract an edge from `name` names is none the model declares, given the half its records
 * are of, or none where it is declared. A contract led by `?` is asked of `pending` alone.
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
    pending->Array.includes(c) ? None : Some(`${c}, undeclared and named in no row`)
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

/** Every edge over one graph that names no contract the model declares, RFC s42ex. */
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
              fault(g, name, halfAcross(g, p.half, x.to_), c)->Option.forEach(
                why => found->Array.push(foundAt([name], `${across}: ${why}`)),
              )
            },
          )
        }
      }
    )
  )
  pending->Array.forEach(c =>
    if !(used->Set.has(c)) && c != "?copies" {
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
    "Does every edge between two of the platform's processes name the contract it carries, declared or filed?",
    violations->Array.map(v => v.text),
    ~notes,
    (),
  )
}
