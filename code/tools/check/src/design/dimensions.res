/**
 * D0 serve, D1 bootstrap, D2 restart, D3 upgrade and D5 contract, `docs/scope.md`. D1 to D3 run on
 * the design and on the as-built graph alike, RFC s42ex.
 */
open Base

/** What one dimension finds over a graph, what it assumes of a boundary, and what it notes. */
type found = {violations: array<finding>, assumed: array<string>, notes: array<string>}

/** Each block's edges internal to it that `when_` selects, by its main name, RFC s42ex. */
let inside = (g: graph, when_: Components.edge => bool) =>
  g.internal
  ->Option.mapOr([], d => d->Dict.toArray)
  ->Array.toSorted(((a, _), (b, _)) => byText(a, b))
  ->Array.flatMap(((m, l)) => l->Array.filter(x => when_(x.edge))->Array.map(x => (m, x)))

/** Each block needing a name it provides itself by an edge `when_` selects, found at the block. */
let itself = (g, when_, needing) =>
  inside(g, when_)->Array.map(((m, x)) =>
    foundAt(
      [m],
      `${m}: ${needing} ${x.edge.to_}, which it provides itself, by ${line(x.from, x.edge)}`,
    )
  )

/**
 * The nodes of `g` judged one by one, every designed one, or on the as-built graph each block
 * running, which `internal` names, a name with no code bringing no edge to judge.
 */
let judged = (g: graph) =>
  g.internal->Option.mapOr(designedIn(g), d =>
    designedIn(g)->Array.filter(((n, _)) => d->Dict.get(n)->Option.isSome)
  )

let firstUp = (x: Components.edge) => x.when_ == #start || x.when_ == #deploy
let start = (x: Components.edge) => x.when_ == #start
let replaces = (x: Components.edge) => x.replaces->Option.getOr(false)

/** D1, whether every component of `g` can come up the first time. */
let bootstrap = (g: graph): found => {
  let d1 = atBoundaries(g, firstUp)
  {
    violations: Array.concatMany(
      cycles(
        n => edgesIn(g, n)->Array.filter(x => firstUp(x) && known(x.to_))->Array.map(x => x.to_),
        g.components->Dict.keysToArray,
      )->Array.map(c => foundAt(c->String.split(" -> "), `cycle: ${c}`)),
      [itself(g, firstUp, "coming up needs"), d1.violations],
    ),
    assumed: d1.assumed,
    notes: [`order: ${order(g, firstUp)->Array.join(" -> ")}`],
  }
}

/** D2, whether every component of `g` can come back from what it kept after a planned stop. */
let restart = (g: graph): found => {
  let d2 = atBoundaries(g, start)
  let isGroundIn = n => componentIn(g, n)->Option.flatMap(p => p.kind) == Some(#ground)
  let rec reachesGround = (n, seen) =>
    if seen->Set.has(n) {
      false
    } else {
      seen->Set.add(n)
      edgesIn(g, n)->Array.some(x =>
        x.hard && known(x.to_) && (isGroundIn(x.to_) || reachesGround(x.to_, seen))
      )
    }
  let keeping = judged(g)->Array.filter(((_, p)) => p.keeps->Option.getOr(false))
  {
    violations: Array.concatMany(
      keeping
      ->Array.filter(((n, _)) => !reachesGround(n, Set.make()))
      ->Array.map(((n, _)) =>
        foundAt([n], `${n} keeps state, but no hard edge carries it to the ground`)
      ),
      [itself(g, start, "restarting needs"), d2.violations],
    ),
    assumed: d2.assumed,
    notes: [
      `order: ${order(g, start)->Array.join(" -> ")}`,
      `keep state of their own: ${keeping->Array.map(((n, _)) => n)->Array.join(", ")}`,
    ],
  }
}

/** Each edge of `g` that reads a format, with the node it leaves and the format it reads. */
let crossingIn = g =>
  designedIn(g)->Array.flatMap(((n, p)) =>
    p.edges->Array.flatMap(x => x.reads->Option.getOr([])->Array.map(reads => (n, x, reads)))
  )

/** D3, whether one component of `g` can be replaced by a new version while the rest runs. */
let upgrade = (g: graph): found => {
  // What replaces a component is the edge marked `replaces`; an edge it deploys others by says
  // nothing.
  let d3 = atBoundaries(g, replaces)
  let replacedInside = inside(g, replaces)->Array.map(((m, _)) => m)
  {
    violations: [
      judged(g)
      ->Array.filter(((n, p)) =>
        !(p.edges->Array.some(replaces) || replacedInside->Array.includes(n))
      )
      ->Array.map(((n, _)) => foundAt([n], `${n}: nothing says what replaces it`)),
      designedIn(g)->Array.flatMap(((n, p)) =>
        p.edges
        ->Array.filter(x => replaces(x) && x.to_ == n)
        ->Array.map(_ => foundAt([n], `${n}: replacing it needs itself`))
      ),
      itself(g, replaces, "replacing it needs"),
      d3.violations,
      crossingIn(g)
      ->Array.filter(((from, _, _)) =>
        !(componentIn(g, from)->Option.mapOr([], p => p.uses)->Array.includes("compat*"))
      )
      ->Array.map(((from, _, reads)) =>
        foundAt([from], `${from} reads ${reads}'s format without compat*`)
      ),
    ]->Array.flat,
    assumed: d3.assumed,
    notes: Components.globalOpen->Array.map(g => `open: ${g}`),
  }
}

let shownAs = (title, question, f: found) =>
  dimension(
    title,
    question,
    f.violations->Array.map(v => v.text),
    ~notes=f.notes,
    ~assumed=f.assumed,
    (),
  )

let run = () => {
  let d0 = atBoundaries(design, serve)
  dimension(
    "D0 Serve",
    "On the correct path, does every operation the products promise reach the ground?",
    d0.violations->Array.map(v => v.text),
    ~assumed=d0.assumed,
    (),
  )
  shownAs(
    "D1 Bootstrap",
    "From the ground and the operator alone, can every component come up the first time?",
    bootstrap(design),
  )
  shownAs(
    "D2 Restart",
    "After a planned stop of everything, can every component come back from what it kept?",
    restart(design),
  )
  shownAs(
    "D3 Upgrade",
    "While the rest runs, can one component be replaced by a new version?",
    upgrade(design),
  )
  dimension(
    "D5 Contract",
    "Is every format a component reads defined at its own layer or below? Carried unread is exempt.",
    crossingIn(design)
    ->Array.filter(((from, _, reads)) => layerOf(reads) > layerOf(from))
    ->Array.map(((from, edge, reads)) =>
      `${from} (${layerName(layerOf(from))}) reads ${reads} (${layerName(
          layerOf(reads),
        )})'s format: ${edge.why}`
    ),
    (),
  )
}
