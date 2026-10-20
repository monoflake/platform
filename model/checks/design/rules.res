/** The rules every dimension stands on, `docs/scope.md`. */
open Base

let run = () => {
  // The rules every dimension stands on: a hard edge points to its own layer or below, a library
  // uses only libraries, and no hard edge closes a cycle.
  let rules = []
  let softUp = []
  designed->Array.forEach(((name, p)) => {
    p.edges->Array.forEach(edge =>
      if known(edge.to_) {
        switch component(edge.to_) {
        | None => rules->Array.push(`${name} -> ${edge.to_}: no such component`)
        | Some(target) =>
          if target.layer > p.layer && target.kind == None {
            (edge.hard ? rules : softUp)->Array.push(line(name, edge))
          }
        }
      }
    )
    p.uses->Array.forEach(lib =>
      if Libraries.libraries->Dict.get(lib) == None {
        rules->Array.push(`${name} uses ${lib}: no such library`)
      }
    )
  })
  Libraries.libraries
  ->Dict.toArray
  ->Array.forEach(((name, lib)) =>
    lib.uses->Array.forEach(use =>
      if Libraries.libraries->Dict.get(use) == None {
        rules->Array.push(`${name} uses ${use}: a component`)
      }
    )
  )
  // The platform runs on itself only while the graph is clean: nothing at layer 0 or below has an
  // edge, hard or soft, to what it runs as an owner, RFC vuanj.
  designed->Array.forEach(((name, p)) =>
    if p.layer <= 0 {
      p.edges->Array.forEach(edge =>
        if component(edge.to_)->Option.flatMap(t => t.asOwner)->Option.getOr(false) {
          rules->Array.push(`runs as an owner, needed below: ${line(name, edge)}`)
        }
      )
    }
  )
  // The organization's half runs on while the platform's cannot be reached: none of its components
  // needs the platform's to serve or to start, and reads a bundle instead, RFC v7v3w.
  let halfOf = to_ =>
    known(to_)
      ? component(to_)->Option.flatMap(p => p.half)
      : boundary(to_)->Option.flatMap(b => b.half)
  designed->Array.forEach(((name, p)) =>
    if p.half == Some(#organization) {
      p.edges->Array.forEach(edge =>
        if (edge.when_ == #serve || edge.when_ == #start) && halfOf(edge.to_) == Some(#platform) {
          rules->Array.push(`the organization's half needs the platform's: ${line(name, edge)}`)
        }
      )
    }
  )
  // What the platform's half holds is configuration, written on the control plane alone, so the
  // data plane runs on while the control plane is lost, `docs/scope.md`.
  let isControl = n => component(n)->Option.flatMap(p => p.control)->Option.getOr(false)
  Records.records->Array.forEach(r => {
    let name = r.kind
    let config = r.half == #platform || r.writes->Array.some(isControl)
    r.writes->Array.forEach(w =>
      switch component(w) {
      | None => rules->Array.push(`${w} writes ${name}: no such component`)
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
      switch component(edge.to_) {
      | Some(t) if t.kind == Some(#ground) && t.half != None && t.half != p.half =>
        rules->Array.push(`stands on the other half's footing: ${line(name, edge)}`)
      | _ => ()
      }
    )
  )
  let hardNext = n => edgesOf(n)->Array.filter(x => x.hard && known(x.to_))->Array.map(x => x.to_)
  cycles(hardNext, components->Dict.keysToArray)->Array.forEach(c =>
    rules->Array.push(`hard cycle: ${c}`)
  )
  cycles(
    n => Libraries.libraries->Dict.get(n)->Option.mapOr([], l => l.uses),
    Libraries.libraries->Dict.keysToArray,
  )->Array.forEach(c => rules->Array.push(`library cycle: ${c}`))
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
}
