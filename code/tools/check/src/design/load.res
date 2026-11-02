/** What each footing keeps, and the rows a day an idle organization asks of it, RFC b8f35. */
open Base

let run = () => {
  // The footing keeps only what is bounded and nothing for an idle organization, RFC b8f35,
  // docs/scope.md. What each step asks of a plan is read where the path is.
  let rows = Footing.rows
  let assumed = Footing.assumed
  let footing = []
  Footing.kept
  ->Dict.toArray
  ->Array.forEach(((name, k)) =>
    if k.grows != #bounded && k.open_ == None {
      footing->Array.push(`${name} grows with ${(k.grows :> string)}: ${k.what}`)
    }
  )
  let idle = assumed.tablets *. rows.idleTablet
  if idle > 0. {
    footing->Array.push(
      `an idle organization writes ${num(idle)} rows a day of its footing, where none is asked`,
    )
  }
  dimension(
    "Footing",
    "Is what each footing keeps bounded, and does an idle organization write none of its rows?",
    footing,
    ~notes=[
      Footing.kept
      ->Dict.toArray
      ->Array.map(((name, k)) =>
        `${name}: ${(k.grows :> string)}${switch k.bound {
          | Some(b) => `, by ${b}`
          | None => ""
          }} -- ${k.what}`
      ),
      [
        `assumed: ${num(assumed.tablets)} tablets an organization, each writing ${num(
            rows.idleTablet,
          )} rows a day idle; each step's load is read where the path is, RFC 8lkuv`,
      ],
    ]->Array.flat,
    (),
  )
}
