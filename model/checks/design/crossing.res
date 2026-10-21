/**
 * Each edge between two of the platform's processes names the contract it carries, one the model
 * declares, an app's WIT or one in `undeclared`. RFC fhg6w.
 */
open Base

let run = () => {
  let found = []
  let interfaces = Contracts.interfaces->Array.map(i => i.name)
  let signed = Signed.signed->Array.map(r => r.name)
  let sections = Signed.sections->Array.map(((n, _)) => `bundle.${n}`)
  let pending = Components.undeclared->Array.map(((n, _)) => `?${n}`)
  let used = Set.make()
  let named = ref(0)
  designed->Array.forEach(((name, p)) =>
    p.edges->Array.forEach(x =>
      if x.replaces != Some(true) && known(x.to_) && x.to_ != "vendor" {
        let at = `${name} -> ${x.to_}`
        // A footing's records are of its half; any other edge's, of the source's.
        let half = component(x.to_)->Option.flatMap(t => t.half)->Option.orElse(p.half)
        switch x.contract {
        | None | Some([]) => found->Array.push(`${at}: names no contract, ${x.why}`)
        | Some(cs) =>
          named := named.contents + 1
          cs->Array.forEach(
            c =>
              if c->String.startsWith("record.") {
                let kind = c->String.slice(~start=String.length("record."))
                switch half {
                | Some(h) if Records.find(h, kind) != None => ()
                | _ => found->Array.push(`${at}: ${c}, no record kind of its half`)
                }
              } else if c == "records" {
                let writes =
                  Records.records->Array.filter(
                    r => Some(r.half) == half && r.writes->Array.includes(name),
                  )
                if writes == [] {
                  found->Array.push(`${at}: records, yet ${name} writes none there`)
                }
              } else if c->String.startsWith("?") {
                used->Set.add(c)
                if !(pending->Array.includes(c)) {
                  found->Array.push(`${at}: ${c}, undeclared and named in no row`)
                }
              } else if (
                !(
                  c == "wit" ||
                  interfaces->Array.includes(c) ||
                  signed->Array.includes(c) ||
                  sections->Array.includes(c)
                )
              ) {
                found->Array.push(`${at}: ${c}, no contract the model declares`)
              },
          )
        }
      }
    )
  )
  pending->Array.forEach(c =>
    if !(used->Set.has(c)) && c != "?copies" {
      found->Array.push(`${c}: undeclared, yet no edge names it`)
    }
  )
  pending->Array.forEach(c =>
    if interfaces->Array.includes(c->String.slice(~start=1)) {
      found->Array.push(`${c}: marked undeclared, yet declared`)
    }
  )
  // Each driver giving a kind of compute is reached at deployment through `deployments`, by what
  // places it, vr5lw, v7v3w.
  Drivers.drivers->Dict.forEachWithKey((d, driver) =>
    if (
      d.implements->Array.some(i => [#function, #instance, #container]->Array.includes(i.kind)) &&
        !(
          designed->Array.some(((_, p)) =>
            p.edges->Array.some(
              x =>
                x.to_ == driver &&
                x.when_ == #deploy &&
                x.contract->Option.getOr([])->Array.includes("deployments"),
            )
          )
        )
    ) {
      found->Array.push(`${driver}: gives compute, yet nothing deploys onto it through deployments`)
    }
  )
  dimension(
    "Crossing",
    "Does every edge between two of the platform's processes name the contract it carries, declared or filed?",
    found,
    ~notes=[`edges naming one: ${int(named.contents)}; undeclared: ${pending->orNone(", ")}`],
    (),
  )
}
