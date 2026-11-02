/** D4 recovery, s1's, run only with `--s1`. */
open Base

let run = () => {
  if args->Array.includes("--s1") {
    Console.log(
      "\n# D4 Recovery (s1): lose one running component, and what stops by hard serve edges",
    )
    designed->Array.forEach(((lost, _)) => {
      let down = Set.fromArray([lost])
      let grew = ref(true)
      while grew.contents {
        grew := false
        designed->Array.forEach(((n, p)) =>
          if (
            !(down->Set.has(n)) &&
            p.edges->Array.some(x => x.hard && serve(x) && down->Set.has(x.to_))
          ) {
            down->Set.add(n)
            grew := true
          }
        )
      }
      down->Set.delete(lost)->ignore
      let rest = down->Set.values->Array.fromIterator
      Console.log(
        `  ${lost->String.padEnd(9, " ")} -> ${rest->Array.length > 0
            ? rest->Array.join(", ")
            : "nothing"}`,
      )
    })
  }
}
