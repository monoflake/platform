/** The footing's design facts scaled for TLC, RFC w0w82 and 8yl4b. */
exception Missing(string)

let fact = name =>
  Footings.interface_.bounds
  ->Option.flatMap(bounds => bounds->Dict.get(name))
  ->Option.getOrThrow(~message=`footing contract lacks ${name}`)

// One tick models fifteen seconds and one row models fifty rows, RFC w0w82.
let scale = {"seconds": 15, "rows": 50}

let scaled = (value, by) => {
  if value <= 0 || mod(value, by) != 0 {
    throw(Missing("footing constant is not a positive multiple of its scale"))
  }
  value / by
}

let constants = () => {
  let seconds = fact("lease_seconds_default")
  let most = fact("lease_seconds_most")
  if seconds > most {
    throw(Missing("footing default lease exceeds its maximum"))
  }
  ignore(scaled(most, scale["seconds"]))
  dict{
    "Seconds": scaled(seconds, scale["seconds"]),
    "Rows": scaled(fact("change_rows"), scale["rows"]),
  }
}

Console.log(JSON.stringifyAny(constants())->Option.getOr("{}"))
