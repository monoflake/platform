/**
 * The roles this half needs of the platform half, each edge naming a contract the role answers and
 * its filler implementing every one, RFC 8lkuv. Unfilled is an assumption, and given a fill a gap.
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
      r.answers
      ->Option.getOr([])
      ->Array.forEach(named =>
        if !(c.answers->Option.getOr([])->Array.includes(named)) {
          found->Array.push(`${name} fills ${role} and implements not ${named}`)
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
