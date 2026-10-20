/** What each footing keeps, and the rows a day each step asks of it, RFC b8f35. */
open Base

let run = () => {
  // The footing, RFC b8f35: what it keeps must be bounded, and what each step asks of the vendor's
  // plan is counted in rows a day, an idle platform's any row at all a violation, docs/scope.md.
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
  let round = x => num(Math.round(x))
  let floor = x => num(Math.floor(x))
  let load = steps->Array.mapWithIndex((step, i) => {
    let production = assumed.production(i)
    let replicated =
      step.cells == Some(#"database organization") && ons(step.foundation, #replicated)
    let organizations =
      assumed.foundation +. (step.cells == Some(#"one each") ? production : replicated ? 1. : 0.)
    let own = organizations *. assumed.tablets *. rows.idleTablet
    // A production organization's footing is a database of its cell, so each of its writes is a commit
    // there, until a replicated log keeps it off the vendor's footing.
    let theirs = replicated ? 0. : production *. assumed.tablets *. rows.idleTablet *. rows.commit
    let idle = own +. theirs
    let plan = step.foundation.plan->Option.getOr(#free)
    let allowed = Footing.allowed(plan)

    // Idle costs nothing beneath, docs/scope.md: a platform at rest writes no row of a footing.
    if idle > 0. {
      footing->Array.push(
        `step ${int(i)}: an idle platform writes ${round(
            idle,
          )} rows a day of the ${(plan :> string)} plan's ${round(allowed)}, where none is asked`,
      )
    }
    let left = Math.max(allowed -. idle, 0.)
    `${int(i)}: idle ${round(idle)} of ${round(allowed)} rows a day (${round(
        idle /. allowed *. 100.,
      )}%); what is left holds ${floor(left /. rows.smallWrite)} small writes, or ${floor(
        left /. rows.largeMiB /. 1024.,
      )} GiB written large; a database's commits write none of it`
  })
  dimension(
    "Footing",
    "Is what each footing keeps bounded, and does an idle platform write none of its rows at any step?",
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
          )} rows a day idle, ${num(
            assumed.foundation,
          )} organizations of the foundation platform's own`,
      ],
      load,
    ]->Array.flat,
    (),
  )
}
