type outcome = Success | Rejected | Unavailable | Unknown

let name = outcome =>
  switch outcome {
  | Success => "success"
  | Rejected => "rejected"
  | Unavailable => "unavailable"
  | Unknown => "unknown"
  }

type heard = Answered({status: int, failure: option<string>}) | Unsent | Lost

type classified = Told(outcome) | Look

let classified = heard =>
  switch heard {
  | Answered({failure: Some("rejected")}) => Told(Rejected)
  | Answered({failure: Some("unavailable")}) => Told(Unavailable)
  | Answered({failure: Some(_)}) => Look
  | Answered({status, failure: None}) => status < 500 ? Told(Success) : Look
  | Unsent => Told(Unavailable)
  | Lost => Look
  }

let failureOf = json =>
  json
  ->JSON.Decode.object
  ->Option.flatMap(object => object->Dict.get("Error"))
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(object => object->Dict.get("failure"))
  ->Option.flatMap(JSON.Decode.string)
