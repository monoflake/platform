/** D0 serve, D1 bootstrap, D2 restart, D3 upgrade and D5 contract, `docs/scope.md`. */
open Base

let run = () => {
  let d0 = atBoundaries(serve)
  dimension(
    "D0 Serve",
    "On the correct path, does every operation the products promise reach the ground?",
    d0.violations,
    ~assumed=d0.assumed,
    (),
  )

  let firstUp = (x: Components.edge) => x.when_ == #start || x.when_ == #deploy
  let d1 = atBoundaries(firstUp)
  dimension(
    "D1 Bootstrap",
    "From the ground and the operator alone, can every component come up the first time?",
    Array.concat(
      cycles(
        n => edgesOf(n)->Array.filter(x => firstUp(x) && known(x.to_))->Array.map(x => x.to_),
        components->Dict.keysToArray,
      )->Array.map(c => `cycle: ${c}`),
      d1.violations,
    ),
    ~notes=[`order: ${order(firstUp)->Array.join(" -> ")}`],
    ~assumed=d1.assumed,
    (),
  )

  let start = (x: Components.edge) => x.when_ == #start
  let d2 = atBoundaries(start)
  let rec reachesGround = (n, seen) =>
    if seen->Set.has(n) {
      false
    } else {
      seen->Set.add(n)
      edgesOf(n)->Array.some(x =>
        x.hard && known(x.to_) && (isGround(x.to_) || reachesGround(x.to_, seen))
      )
    }
  let keeps = (p: Components.component) => p.keeps->Option.getOr(false)
  dimension(
    "D2 Restart",
    "After a planned stop of everything, can every component come back from what it kept?",
    Array.concat(
      designed
      ->Array.filter(((n, p)) => keeps(p) && !reachesGround(n, Set.make()))
      ->Array.map(((n, _)) => `${n} keeps state, but no hard edge carries it to the ground`),
      d2.violations,
    ),
    ~notes=[
      `order: ${order(start)->Array.join(" -> ")}`,
      `keep state of their own: ${designed
        ->Array.filter(((_, p)) => keeps(p))
        ->Array.map(((n, _)) => n)
        ->Array.join(", ")}`,
    ],
    ~assumed=d2.assumed,
    (),
  )

  let crossing =
    designed->Array.flatMap(((n, p)) =>
      p.edges->Array.flatMap(x => x.reads->Option.getOr([])->Array.map(reads => (n, x, reads)))
    )
  let replaces = (x: Components.edge) => x.replaces->Option.getOr(false)
  // What replaces a component is the edge marked `replaces`; an edge it deploys others by says
  // nothing.
  let d3 = atBoundaries(replaces)
  dimension(
    "D3 Upgrade",
    "While the rest runs, can one component be replaced by a new version?",
    [
      designed
      ->Array.filter(((_, p)) => !(p.edges->Array.some(replaces)))
      ->Array.map(((n, _)) => `${n}: nothing says what replaces it`),
      designed->Array.flatMap(((n, p)) =>
        p.edges
        ->Array.filter(x => replaces(x) && x.to_ == n)
        ->Array.map(_ => `${n}: replacing it needs itself`)
      ),
      d3.violations,
      crossing
      ->Array.filter(((from, _, _)) =>
        !(component(from)->Option.mapOr([], p => p.uses)->Array.includes("compat*"))
      )
      ->Array.map(((from, _, reads)) => `${from} reads ${reads}'s format without compat*`),
    ]->Array.flat,
    ~notes=Components.globalOpen->Array.map(g => `open: ${g}`),
    ~assumed=d3.assumed,
    (),
  )

  dimension(
    "D5 Contract",
    "Is every format a component reads defined at its own layer or below? Carried unread is exempt.",
    crossing
    ->Array.filter(((from, _, reads)) => layerOf(reads) > layerOf(from))
    ->Array.map(((from, edge, reads)) =>
      `${from} (${layerName(layerOf(from))}) reads ${reads} (${layerName(
          layerOf(reads),
        )})'s format: ${edge.why}`
    ),
    (),
  )
}
