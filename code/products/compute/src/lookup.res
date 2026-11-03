type steps = {committed: array<int>, finished: bool}

type found = Finished | NotSeen | Open(option<int>)

let looked = async (~steps, ~expires, ~deadline, ~now, ~wait) => {
  let started = now()
  let rec ask = async () => {
    let answer = await steps()
    let elapsed = now() -. started
    let known = switch answer {
    | Ok(value) => value
    | Error(_) => {committed: [], finished: false}
    }
    let last = known.committed->Array.reduce(None, (last, sequence) =>
      switch last {
      | None => Some(sequence)
      | Some(previous) =>
        Some(
          if sequence > previous {
            sequence
          } else {
            previous
          },
        )
      }
    )
    if known.finished {
      (Finished, elapsed)
    } else if last == None && started +. elapsed > expires {
      (NotSeen, elapsed)
    } else if elapsed >= deadline {
      (Open(last), elapsed)
    } else {
      let remaining = deadline -. elapsed
      await wait(
        if remaining < 1. {
          remaining
        } else {
          1.
        },
      )
      await ask()
    }
  }
  await ask()
}
