open Base

/**
 * Whether `name` is a product at layer 0 the platform beneath answers, by its own name or any of
 * its answers, RFC 94y0d's way down.
 */
let throughProduct = (~lookup=component, name) => {
  let products = Provided.beneath.answers->Option.getOr([])
  lookup(name)->Option.mapOr(false, (c: Components.component) =>
    c.layer == 0 &&
      (products->Array.includes(name) ||
        c.answers->Option.getOr([])->Array.some(a => products->Array.includes(a)))
  )
}

/** The contracts the filled name answers that the name taken from beneath does not, btzlt. */
let unanswered = (~lookup=component, filled, taken) => {
  let answers = n => lookup(n)->Option.flatMap(c => c.answers)->Option.getOr([])
  filled == taken ? [] : answers(filled)->Array.filter(c => !(answers(taken)->Array.includes(c)))
}

/** Each name a column takes down through anything but a product at layer 0, RFC btzlt. */
let downward = (~lookup=component, column, d: Provided.deployed) =>
  Realized.filledBeneath(d)
  ->Array.filter(b => !throughProduct(~lookup, b.name))
  ->Array.map(b => (
    "Beneath",
    foundAt(
      [b.filled],
      `${column} fills ${b.filled} by ${b.name} in ${b.deployment}, no product at layer 0 beneath answers, against RFC 94y0d`,
    ),
  ))

/**
 * Whether a name is provided in a deployment, by a fill there or a block there declaring it, an
 * unbuilt block too, since its own column reports it.
 */
let providedThere = (~declared=Provided.all, d: Provided.deployed, name) =>
  d.fills->Array.some(((n, _)) => n == name) ||
    Realized.blocksIn(d)->Array.some(m =>
      Realized.provides({mains: [], declared}, m)->Array.includes(name)
    )

/** Where a chain of `Beneath` from a name ends, each deployment it passes named. */
type ending =
  | Reached
  | NotThere(string, string)
  | NoDeployment(string)
  | Back(string)

/** A chain of `Beneath` followed from `name` in `deployment` to its end, btzlt. */
let rec followed = (~deployments: dict<Provided.deployed>, passed, deployment, name) =>
  if passed->Array.includes(deployment) {
    Back(deployment)
  } else {
    switch deployments->Dict.get(deployment) {
    | None => NoDeployment(deployment)
    | Some(there) =>
      switch there.fills->Array.find(((n, _)) => n == name) {
      | Some((_, Beneath({deployment: next, name: taken}))) =>
        followed(~deployments, passed->Array.concat([deployment]), next, taken)
      | Some((_, Block(_) | Vendor(_) | Workload(_) | Import(_))) => Reached
      | None => providedThere(there, name) ? Reached : NotThere(deployment, name)
      }
    }
  }

/** The deployments a column stands on, each a `Beneath` of it names, its own aside. */
let standsOn = (column, d: Provided.deployed) =>
  Realized.union([Realized.filledBeneath(d)->Array.map(b => b.deployment)])->Array.filter(n =>
    n != column
  )

/** A chain of deployments a column stands on that comes back to one already passed, if any. */
let circling = (~deployments: dict<Provided.deployed>, column, d) => {
  let rec walk = (path, at, d) =>
    standsOn(at, d)->Array.reduce(None, (found, next) =>
      switch found {
      | Some(_) => found
      | None if path->Array.includes(next) => Some(path->Array.concat([next]))
      | None =>
        deployments
        ->Dict.get(next)
        ->Option.flatMap(there => walk(path->Array.concat([next]), next, there))
      }
    )
  walk([column], column, d)
}

/**
 * What a column's `Beneath` fills mistake, btzlt, each at the names it fills: one deployment
 * beneath, never its own, a chain of them followed to a name provided, never coming back, and
 * every contract the filled name answers answered by the name taken.
 */
let mistakenBeneath = (
  ~deployments=Provided.deployments,
  ~lookup=component,
  column,
  d: Provided.deployed,
) => {
  let fills = Realized.filledBeneath(d)
  let all = fills->Array.map(b => b.filled)
  let named = Realized.union([fills->Array.map(b => b.deployment)])
  let circled = circling(~deployments, column, d)
  Array.concatMany(
    named->Array.length > 1
      ? [
          foundAt(
            all,
            `${column} stands on ${named->Array.join(", ")}, more than one deployment beneath`,
          ),
        ]
      : [],
    [
      circled->Option.mapOr([], chain => {
        let passed = chain->Array.join(" -> ")
        [
          foundAt(
            all,
            `${column} stands on a chain of deployments coming back to one passed, ${passed}`,
          ),
        ]
      }),
      fills->Array.flatMap(b => {
        let by = `${b.filled} is filled by ${b.name} in ${b.deployment}`
        let texts = if b.deployment == column {
          [`${b.filled} is filled from beneath by ${column}, the deployment's own`]
        } else {
          switch followed(~deployments, [column], b.deployment, b.name) {
          | Reached => []
          | NoDeployment(there) if there == b.deployment => [
              `${b.filled} is filled from beneath by ${there}, which is no deployment`,
            ]
          | NoDeployment(there) => [`${by}, a chain reaching ${there}, which is no deployment`]
          | NotThere(there, _) if there == b.deployment => [`${by}, which provides it not there`]
          | NotThere(there, n) => [
              `${by}, a chain ending at ${n} in ${there}, which provides it not there`,
            ]
          | Back(_) if circled != None => []
          | Back(there) => [`${by}, a chain coming back to ${there}, already passed`]
          }
        }
        let missing = unanswered(~lookup, b.filled, b.name)
        let unmet =
          missing == [] ? [] : [`${by}, which leaves ${missing->Array.join(", ")} unanswered`]
        Array.concat(texts, unmet)->Array.map(t => foundAt([b.filled], t))
      }),
    ],
  )
}
