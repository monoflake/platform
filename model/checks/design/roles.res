/**
 * The roles this half needs of the platform half and of the drivers, each edge naming a contract
 * the role answers and its filler meeting it, RFCs 8lkuv and 7ykg6. Unfilled is an assumption.
 */
open Base

let kindText = (k: Drivers.kind) =>
  `${(k.kind :> string)}${k.contract->Option.mapOr("", c =>
      ` by ${c} v${k.version->Option.mapOr("?", v => int(v))}`
    )}`
let runtimeText = (r: Drivers.runtime) =>
  `${r.name} taking ${r.takes} on ${r.stands->Array.join("+")}`

/** Where what is given differs from what is asked, each part compared as a set. */
let differs = (at, what, asked: array<string>, given: array<string>) =>
  Array.concat(
    asked
    ->Array.filter(a => !(given->Array.includes(a)))
    ->Array.map(a => `${at}: gives not ${what} ${a}, which is asked`),
    given
    ->Array.filter(g => !(asked->Array.includes(g)))
    ->Array.map(g => `${at}: gives ${what} ${g}, which is not asked`),
  )

/** What a driver role asks that is not so of itself, its grounds, kinds and contracts. */
let consistent = (role, r: Components.component, d: Drivers.driver) => {
  let found = []
  let grounds = Set.fromArray(
    d.grounds
    ->Array.flatMap(Resources.groundOf)
    ->Array.flatMap(n => Resources.get(Resources.resources, n).gives),
  )
  let kinds = d.kinds->Array.map(k => k.kind)
  grounds->Set.forEach(k =>
    if !(kinds->Array.includes(k)) {
      found->Array.push(`${role}: its grounds give ${(k :> string)}, which it is not asked`)
    }
  )
  kinds->Array.forEach(k =>
    if !(grounds->Set.has(k)) {
      found->Array.push(`${role}: asked ${(k :> string)}, which its grounds give not`)
    }
  )
  d.kinds->Array.forEach(k =>
    switch (k.contract, k.version) {
    | (Some(c), None) => found->Array.push(`${role}: ${c} is no contract this model declares`)
    | (Some(_), Some(_)) | (None, _) => ()
    }
  )
  let contracts =
    d.kinds->Array.filterMap(k => k.contract)->Array.concat(["management"])->Set.fromArray
  let answers = r.answers->Option.getOr([])
  if (
    answers->Array.length != contracts->Set.size ||
      !(answers->Array.every(a => contracts->Set.has(a)))
  ) {
    found->Array.push(`${role}: answers not management and its kinds' contracts alone`)
  }
  found
}

/** Where a driver fill misses what a role asks, every part as asked, RFC 7ykg6. */
let meets = (role, asked: Drivers.driver, given: Drivers.driver) =>
  Array.concatMany(
    differs(
      role,
      "ground",
      asked.grounds->Array.map(g => (g :> string)),
      given.grounds->Array.map(g => (g :> string)),
    ),
    [
      differs(role, "kind", asked.kinds->Array.map(kindText), given.kinds->Array.map(kindText)),
      differs(
        role,
        "runtime",
        asked.runtimes->Array.map(runtimeText),
        given.runtimes->Array.map(runtimeText),
      ),
      asked.management == given.management
        ? []
        : [
            `${role}: gives management v${int(given.management)}, where v${int(
                asked.management,
              )} is asked`,
          ],
    ],
  )

let run = () => {
  let found = []
  let roles = Components.own->Dict.toArray->Array.filter(((_, c)) => c.kind == Some(#provided))
  let given = Components.given->Dict.toArray
  let filling = given != []
  let notes = []
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
    switch (Drivers.asked->Dict.get(role), fillers) {
    | (Some(asked), []) =>
      found->Array.pushMany(consistent(role, r, asked))
      switch Drivers.given->Option.map(d => d->Dict.get(role)) {
      | None => notes->Array.push(`${role}: unfilled, an assumption`)
      | Some(None) => found->Array.push(`${role}: the drivers given fill it not`)
      | Some(Some(d)) =>
        found->Array.pushMany(meets(role, asked, d))
        notes->Array.push(`${role}: filled by the drivers given`)
      }
    | (Some(_), _) => found->Array.push(`${role}: a driver role, filled by a component`)
    | (None, []) if filling => found->Array.push(`${role}: nothing given fills it`)
    | (None, []) => notes->Array.push(`${role}: unfilled, an assumption`)
    | (None, [(name, c)]) =>
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
      notes->Array.push(`${role}: ${name}`)
    | (None, many) =>
      found->Array.push(
        `${role}: filled ${int(many->Array.length)} times, by ${many
          ->Array.map(((name, _)) => name)
          ->Array.join(", ")}`,
      )
    }
  })
  Drivers.given
  ->Option.getOr(Dict.make())
  ->Dict.keysToArray
  ->Array.forEach(name =>
    if Drivers.asked->Dict.get(name)->Option.isNone {
      found->Array.push(`${name}: given as a driver, yet no driver role is so named`)
    }
  )
  dimension(
    "Roles",
    "Does every edge to a role name a contract it answers, and is each role filled once, where it stands, a driver as it is asked?",
    found,
    ~notes,
    (),
  )
}
