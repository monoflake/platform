type asked = {began: float, ended: float, answer: result<unit, string>}

type tally = {
  path: string,
  asked: int,
  answered: int,
  failed: int,
  longest: float,
  reasons: array<(string, int)>,
}

/** A reason's first line, short enough for the report. */
let reasonOf = why => {
  let first = why->String.split("\n")->Array.get(0)->Option.getOr("")->String.trim
  first->String.length > 100 ? first->String.slice(~start=0, ~end=100) ++ "..." : first
}

let tally = (~path, ~from, ~until, asks) => {
  let ends =
    asks
    ->Array.filterMap(a => a.answer->Result.isOk ? Some(a.ended) : None)
    ->Array.toSorted(Float.compare)
  let last = asks->Array.reduce(until, (latest, a) => Math.max(latest, a.ended))
  let (_, longest) =
    [...ends, last]->Array.reduce((from, 0.), ((before, most), at) => (
      at,
      Math.max(most, at -. before),
    ))
  let counted: dict<int> = dict{}
  asks->Array.forEach(a =>
    switch a.answer {
    | Ok() => ()
    | Error(why) =>
      let reason = reasonOf(why)
      counted->Dict.set(reason, counted->Dict.get(reason)->Option.getOr(0) + 1)
    }
  )
  let answered = ends->Array.length
  {
    path,
    asked: asks->Array.length,
    answered,
    failed: asks->Array.length - answered,
    longest,
    reasons: counted->Dict.toArray->Array.toSorted(((_, a), (_, b)) => Int.compare(b, a)),
  }
}

let held = t => t.asked > 0 && t.failed == 0

let line = t => {
  let int = Int.toString
  let reasons = t.reasons->Array.map(((reason, n)) => `, ${int(n)} times ${reason}`)->Array.join("")
  `${t.path}: asked ${int(t.asked)}, answered ${int(t.answered)}, failed ${int(
      t.failed,
    )}, longest gap ${(t.longest /. 1000.)->Float.toFixed(~digits=1)}s${reasons}`
}
