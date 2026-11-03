type answer =
  | Known({outcome: option<string>, committed: array<int>, expires: float, finished: bool})
  | NotFound
  | Forgotten

let answered = (~recorded, ~steps, ~issued, ~now, ~retention) =>
  if now > issued +. retention {
    Forgotten
  } else {
    switch recorded {
    | None => NotFound
    | Some((expires, outcome)) =>
      let (committed, finished) = steps->Option.getOr(([], false))
      Known({outcome, committed, expires, finished})
    }
  }

let refused = reason => JSON.Object(
  dict{
    "Error": JSON.Object(
      dict{
        "failure": JSON.String("rejected"),
        "reason": JSON.String(reason),
        "message": JSON.String(Envelope.Contracts.messages->Dict.get(reason)->Option.getOr(reason)),
      },
    ),
  },
)

let json = (~id, answer) =>
  switch answer {
  | NotFound => refused("not_found")
  | Forgotten => refused("forgotten")
  | Known({outcome, committed, expires, finished}) =>
    let status = dict{
      "id": JSON.String(id),
      "committed": JSON.Array(committed->Array.map(step => JSON.Number(step->Int.toFloat))),
      "expires": JSON.Number(expires),
      "finished": JSON.Boolean(finished),
    }
    outcome->Option.forEach(outcome => status->Dict.set("outcome", JSON.String(outcome)))
    JSON.Object(dict{"Ok": JSON.Object(status)})
  }
