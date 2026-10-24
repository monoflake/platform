/** The rules every dimension stands on, `docs/scope.md`. */
open Base

/** Every rule a graph breaks, run on the design and on the as-built graph alike, RFC s42ex. */
let check = (g: graph): checked => {
  // A hard edge points to its own layer or below, a library uses only libraries, and no hard edge
  // closes a cycle.
  let rules = []
  let softUp = []
  let nodes = designedIn(g)
  nodes->Array.forEach(((name, p)) => {
    p.edges->Array.forEach(edge =>
      if known(edge.to_) {
        switch componentIn(g, edge.to_) {
        | None => rules->Array.push(foundAt([name], `${name} -> ${edge.to_}: no such component`))
        | Some(target) =>
          if target.layer > p.layer && target.kind == None {
            if edge.hard {
              rules->Array.push(foundAt([name], line(name, edge)))
            } else {
              softUp->Array.push(line(name, edge))
            }
          }
        }
      }
    )
    p.uses->Array.forEach(lib =>
      if Libraries.libraries->Dict.get(lib) == None {
        rules->Array.push(foundAt([name], `${name} uses ${lib}: no such library`))
      }
    )
  })
  Libraries.libraries
  ->Dict.toArray
  ->Array.forEach(((name, lib)) =>
    lib.uses->Array.forEach(use =>
      if Libraries.libraries->Dict.get(use) == None {
        rules->Array.push(foundAt([name], `${name} uses ${use}: a component`))
      }
    )
  )
  // Nothing at layer 0 or below has an edge to what it runs as an owner, RFC vuanj.
  nodes->Array.forEach(((name, p)) =>
    if p.layer <= 0 {
      p.edges->Array.forEach(edge =>
        if componentIn(g, edge.to_)->Option.flatMap(t => t.asOwner)->Option.getOr(false) {
          rules->Array.push(foundAt([name], `runs as an owner, needed below: ${line(name, edge)}`))
        }
      )
    }
  )
  // No component of the organization's half needs the platform's to serve or start, reading a
  // bundle instead, RFC v7v3w.
  let halfOf = to_ =>
    known(to_)
      ? componentIn(g, to_)->Option.flatMap(p => p.half)
      : boundary(to_)->Option.flatMap(b => b.half)
  nodes->Array.forEach(((name, p)) =>
    if p.half == Some(#organization) {
      p.edges->Array.forEach(edge =>
        if (edge.when_ == #serve || edge.when_ == #start) && halfOf(edge.to_) == Some(#platform) {
          rules->Array.push(
            foundAt([name], `the organization's half needs the platform's: ${line(name, edge)}`),
          )
        }
      )
    }
  )
  // What the platform's half holds is configuration, written on the control plane alone, so the
  // data plane runs on while the control plane is lost, `docs/scope.md`.
  let isControl = n => componentIn(g, n)->Option.flatMap(p => p.control)->Option.getOr(false)
  g.records->Array.forEach(r => {
    let name = r.kind
    let config = r.half == #platform || r.writes->Array.some(isControl)
    r.writes->Array.forEach(w =>
      switch componentIn(g, w) {
      | None => rules->Array.push(foundAt([w], `${w} writes ${name}: no such component`))
      | Some(writer) =>
        if config && !isControl(w) {
          rules->Array.push(
            foundAt([w], `the data plane writes configuration: ${w} writes ${name}, ${r.from}`),
          )
        } else if r.half == #platform && writer.half != Some(#platform) {
          rules->Array.push(
            foundAt([w], `an organization writes the platform's: ${w} writes ${name}, ${r.from}`),
          )
        }
      }
    )
  })
  // A footing is the platform's or an organization's, and each half stands on its own alone, by any
  // edge, RFC vr5lw.
  nodes->Array.forEach(((name, p)) =>
    p.edges->Array.forEach(edge =>
      switch componentIn(g, edge.to_) {
      | Some(t) if t.kind == Some(#ground) && t.half != None && t.half != p.half =>
        rules->Array.push(
          foundAt([name], `stands on the other half's footing: ${line(name, edge)}`),
        )
      | _ => ()
      }
    )
  )
  let hardNext = n =>
    edgesIn(g, n)->Array.filter(x => x.hard && known(x.to_))->Array.map(x => x.to_)
  cycles(hardNext, g.components->Dict.keysToArray)->Array.forEach(c =>
    rules->Array.push(foundAt(c->String.split(" -> "), `hard cycle: ${c}`))
  )
  cycles(
    n => Libraries.libraries->Dict.get(n)->Option.mapOr([], l => l.uses),
    Libraries.libraries->Dict.keysToArray,
  )->Array.forEach(c => rules->Array.push(foundAt(c->String.split(" -> "), `library cycle: ${c}`)))
  {
    violations: rules,
    notes: [
      `soft edges upward, allowed: ${softUp->orNone("; ")}`,
      `no half, since they run nothing: ${nodes
        ->Array.filter(((_, p)) => p.half == None)
        ->Array.map(((n, _)) => n)
        ->orNone(", ")}`,
    ],
  }
}

let run = () => {
  let {violations, notes} = check(design)
  dimension(
    "Rules",
    "Does every hard edge point down, every library use only libraries, nothing below need an owner, no organization need the platform's half to serve or start, the data plane write no configuration, and each half stand on its own footing alone?",
    violations->Array.map(v => v.text),
    ~notes,
    (),
  )
}
