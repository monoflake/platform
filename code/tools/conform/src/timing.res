type stage = {name: string, milliseconds: float}
type t = {now: unit => float, stages: array<stage>}

let make = (~now=Date.now, ()) => {now, stages: []}

let record = (timing, name, started) =>
  timing.stages->Array.push({name, milliseconds: timing.now() -. started})

let run = (timing, name, action) => {
  let started = timing.now()
  let result = action()
  record(timing, name, started)
  result
}

let runAsync = async (timing, name, action) => {
  let started = timing.now()
  let result = await action()
  record(timing, name, started)
  result
}

let lines = timing =>
  timing.stages->Array.map(stage =>
    `conform: took ${(stage.milliseconds /. 1000.)->Float.toFixed(~digits=1)}s, ${stage.name}`
  )
