/**
 * The roles this half needs of the platform half, RFC 8lkuv: an edge to one names a contract it
 * answers, and what fills one stands where it does -- its layer, its half, a control as it is --
 * with the role's own edges into this half exactly, the rest of its edges the other repository's.
 * One filler a role; checked alone, a role unfilled is an assumption, and given a fill, a gap.
 */
open Base

let run = () => {
  let found = []
  let roles = Components.own->Dict.toArray->Array.filter(((_, c)) => c.kind == Some(#provided))
  let given = Components.given->Dict.toArray
  let filling = given != []
  roles->Array.forEach(((role, r)) => {
    Components.own
    ->Dict.toArray
    ->Array.forEach(((from, c)) =>
      c.edges->Array.forEach(
        edge =>
          if edge.to_ == role {
            edge.contract
            ->Option.getOr([])
            ->Array.forEach(
              named =>
                if !(r.answers->Option.getOr([])->Array.includes(named)) {
                  found->Array.push(`${from} -> ${role}: ${named} is no contract ${role} answers`)
                },
            )
          },
      )
    )
    let fillers = given->Array.filter(((_, c)) => c.fills == Some(role))
    switch fillers {
    | [] if filling => found->Array.push(`${role}: nothing given fills it`)
    | [] => ()
    | [(name, c)] =>
      if c.layer != r.layer || c.half != r.half || c.control != r.control {
        found->Array.push(`${name} fills ${role} at another layer, half or control than it has`)
      }
      // Into this half the filler reaches exactly as the role says; within its own, as it likes.
      let key = (edge: Components.edge) =>
        `${edge.to_} ${(edge.when_ :> string)}/${edge.hard ? "hard" : "soft"}${edge.replaces ==
            Some(true)
            ? " replaces"
            : ""}`
      let own =
        c.edges
        ->Array.filter(edge => Components.given->Dict.get(edge.to_)->Option.isNone)
        ->Array.map(key)
      let declared = r.edges->Array.map(key)
      own->Array.forEach(k =>
        if !(declared->Array.includes(k)) {
          found->Array.push(`${name} -> ${k}: an edge into this half ${role} does not declare`)
        }
      )
      declared->Array.forEach(k =>
        if !(own->Array.includes(k)) {
          found->Array.push(`${name} lacks ${role}'s edge ${k}`)
        }
      )
    | many =>
      found->Array.push(
        `${role}: filled ${int(many->Array.length)} times, by ${many
          ->Array.map(((name, _)) => name)
          ->Array.join(", ")}`,
      )
    }
  })
  dimension(
    "Roles",
    "Does every edge to a role name a contract it answers, and is each role filled once, where it stands?",
    found,
    ~notes=roles->Array.map(((role, _)) =>
      `${role}: ${Components.filler->Dict.get(role)->Option.getOr("unfilled, an assumption")}`
    ),
    (),
  )
}
