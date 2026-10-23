module Tally = Lose.Tally

type counted = {
  path: string,
  made: int,
  answered: int,
  refused: int,
  failed: int,
  longest: float,
  reasons: array<(string, int)>,
}

/** The ask as lose's tally takes it, its longest silence measured the same. */
let tallied = ({began, ended, outcome}: Load.asked): Tally.asked => {
  began,
  ended,
  answer: switch outcome {
  | Answered => Ok()
  | Refused(why) => Error(`refused, ${why}`)
  | Failed(why) => Error(why)
  },
}

let count = (~path, ~from, ~until, asks: array<Load.asked>) => {
  let within = asks->Array.filter(a => a.began >= from && a.began < until)
  let t = Tally.tally(~path, ~from, ~until, within->Array.map(tallied))
  let refused =
    within
    ->Array.filter(a =>
      switch a.outcome {
      | Refused(_) => true
      | Answered | Failed(_) => false
      }
    )
    ->Array.length
  {
    path,
    made: t.asked,
    answered: t.answered,
    refused,
    failed: t.failed - refused,
    longest: t.longest,
    reasons: t.reasons,
  }
}

let held = c => c.made > 0 && c.refused == 0 && c.failed == 0

let line = c => {
  let int = Int.toString
  let reasons = c.reasons->Array.map(((reason, n)) => `, ${int(n)} times ${reason}`)->Array.join("")
  `${c.path}: made ${int(c.made)}, answered 200 ${int(c.answered)}, refused ${int(
      c.refused,
    )}, failed ${int(c.failed)}, longest gap ${(c.longest /. 1000.)
      ->Float.toFixed(~digits=1)}s${reasons}`
}
