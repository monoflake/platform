/** The public boundary between organizations, RFC nge39. */
open Base

let exportsOf = (d: Provided.deployed) => d.exports->Option.getOr([])

let localApp = (d: Provided.deployed, app) =>
  d.fills->Array.some(((name, f)) =>
    name == app &&
      switch f {
      | Block(_) | Workload(_) => true
      | Vendor(_) | Beneath(_) | Import(_) => false
      }
  )

let https = endpoint =>
  /^https:\/\/[a-zA-Z0-9][a-zA-Z0-9.-]*(?::[0-9]+)?(?:\/[^\s]*)?$/->RegExp.test(endpoint)

/** Every crossing is explicit, and an import stops at the source's public export. */
let check = (~deployments=Provided.deployments, ~lookup=component, ()): checked => {
  let found = []
  deployments
  ->Dict.toArray
  ->Array.forEach(((column, d)) => {
    let add = (name, why) => found->Array.push(foundAt([name], `${column}: ${why}, RFC nge39`))
    let exports = exportsOf(d)
    exports->Array.forEach(e => {
      if d.organization == None || d.organization == Some("") {
        add(e.name, `export ${e.name} has no organization`)
      }
      if !localApp(d, e.app) {
        add(e.name, `export ${e.name} names ${e.app}, no app of its own`)
      }
      if !https(e.endpoint) {
        add(e.name, `export ${e.name} requires a public HTTPS endpoint`)
      }
      if exports->Array.filter(other => other.name == e.name)->Array.length != 1 {
        add(e.name, `export ${e.name} is declared more than once`)
      }
    })
    d.fills->Array.forEach(((filled, f)) =>
      switch f {
      | Beneath({deployment, name}) =>
        deployments
        ->Dict.get(deployment)
        ->Option.forEach(
          there => {
            if d.organization != there.organization {
              add(
                filled,
                `internal path ${filled} -> ${name} in ${deployment} crosses organizations; use an import of an export`,
              )
            }
          },
        )
      | Import({deployment, name}) =>
        switch deployments->Dict.get(deployment) {
        | None => add(filled, `import ${filled} names ${deployment}, no deployment`)
        | Some(there) =>
          if (
            d.organization == None ||
            d.organization == Some("") ||
            there.organization == None ||
            there.organization == Some("")
          ) {
            add(filled, `import ${filled} requires both organizations`)
          } else if d.organization == there.organization {
            add(filled, `import ${filled} requires another organization`)
          }
          switch exportsOf(there)->Array.filter(e => e.name == name) {
          | [e] =>
            if !localApp(there, e.app) || !https(e.endpoint) {
              add(filled, `import ${filled} names ${name} in ${deployment}, no public app export`)
            }
            let required =
              lookup(filled)->Option.mapOr(
                [],
                c => c.answers->Option.getOr([Crossing.base(filled)]),
              )
            let missing = required->Array.filter(c => !(e.contracts->Array.includes(c)))
            if missing != [] {
              add(filled, `import ${filled} leaves ${missing->Array.join(", ")} unanswered`)
            }
          | _ =>
            add(filled, `import ${filled} names ${name}, which ${deployment} does not export once`)
          }
        }
      | Block(_) | Vendor(_) | Workload(_) => ()
      }
    )
  })
  {violations: found, notes: []}
}

let run = () => {
  let {violations, notes} = check()
  dimension(
    "Imports",
    "Does every path between organizations end at a public HTTPS export, explicitly imported?",
    violations->Array.map(v => v.text),
    ~notes,
    (),
  )
}
