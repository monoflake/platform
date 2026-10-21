/** Every boundary, whether its contract is written, and whether theory is complete. */
open Base

let run = () => {
  Console.log("\n# Boundaries, and whether each has its contract")
  let needed: Map.t<string, array<string>> = Map.make()
  designed->Array.forEach(((name, p)) =>
    p.edges->Array.forEach(edge =>
      if !known(edge.to_) {
        needed->Map.set(
          edge.to_,
          needed->Map.get(edge.to_)->Option.getOr([])->Array.concat([`${name} ${tag(edge)}`]),
        )
      }
    )
  )
  needed->Map.forEachWithKey((from, to_) => {
    let b = boundary(to_)
    Console.log(
      `  ${contracted(to_) ? "contract" : "none    "} ${to_->String.padEnd(
          14,
          " ",
        )} ${from->Array.join(", ")}`,
    )
    Console.log(
      `           kept by: ${switch b->Option.flatMap(b => b.keptBy) {
        | Some(k) =>
          `${k}${switch b->Option.flatMap(b => b.triage) {
            | Some(t) => ` [${(t :> string)}]`
            | None => ""
            }}`
        | None => "undecided"
        }}`,
    )
  })
  Boundaries.boundaries
  ->Dict.keysToArray
  ->Array.forEach(to_ =>
    if !(needed->Map.has(to_)) {
      Console.log(`  unused   ${to_}: no edge needs it`)
    }
  )
  needed
  ->Map.keys
  ->Array.fromIterator
  ->Array.forEach(to_ =>
    if boundary(to_) == None {
      Console.log(`  unlisted ${to_}: add it to boundaries`)
    }
  )

  // Every boundary is kept by someone and sorted, the completion rule of `docs/method.md`.
  let unsorted =
    needed
    ->Map.keys
    ->Array.fromIterator
    ->Array.filter(to_ =>
      boundary(to_)->Option.flatMap(b => b.keptBy) == None ||
        boundary(to_)->Option.flatMap(b => b.triage) == None
    )
  Console.log(
    `\n# Completion\n  ${unsorted->Array.length > 0
        ? `not yet kept and sorted: ${unsorted->Array.join(", ")}`
        : "every boundary is kept and sorted"}`,
  )
}
