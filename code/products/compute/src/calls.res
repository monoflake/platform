type execute = JSON.t => promise<JSON.t>
type issuer = {mutable last: float, mutable sequence: int}

let issuer = () => {last: -1., sequence: 0}

let issued = (issuer, ~now) => {
  if now < 0. || now > 281474976710655. || now != Math.floor(now) {
    None
  } else {
    let later = now > issuer.last
    if !later && issuer.sequence == 65535 {
      None
    } else {
      if later {
        issuer.last = now
        issuer.sequence = 0
      } else {
        issuer.sequence = issuer.sequence + 1
      }
      let milliseconds = issuer.last->Float.toString(~radix=16)->String.padStart(12, "0")
      let sequence = issuer.sequence->Int.toString(~radix=16)->String.padStart(4, "0")
      Some(milliseconds ++ sequence)
    }
  }
}

let issuedAt = id =>
  id->String.length == 16 && /^[0-9a-f]{16}$/->RegExp.test(id)
    ? Some(Float.parseInt(id->String.slice(~start=0, ~end=12), ~radix=16))
    : None

type record = {id: string, app: float, function: string, expires: float, outcome: option<string>}

let object = fields => JSON.Object(Dict.fromArray(fields))
let text = value => object([("name", JSON.String("text")), ("value", JSON.String(value))])
let integer = value => object([("name", JSON.String("integer")), ("value", JSON.Number(value))])
let null = object([("name", JSON.String("null"))])
let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
let string = (json, name) => json->field(name)->Option.flatMap(JSON.Decode.string)
let invalid = "the records database answered an invalid result"

let run = async (~execute, sql, parameters) => {
  let statement = object([("sql", JSON.String(sql)), ("parameters", JSON.Array(parameters))])
  try {
    let answer = await execute(object([("statements", JSON.Array([statement]))]))
    switch answer->field("Error") {
    | Some(error) => Error(error->string("reason")->Option.getOr(invalid))
    | None =>
      switch answer->field("Ok")->Option.flatMap(ok => ok->field("results")) {
      | Some(results) =>
        switch results->JSON.Decode.array {
        | Some([result]) => Ok(result)
        | Some(_) | None => Error(invalid)
        }
      | None => Error(invalid)
      }
    }
  } catch {
  | JsExn(error) => Error(error->JsExn.message->Option.getOr(invalid))
  }
}

let made = async (~execute) => {
  let result = await run(
    ~execute,
    "CREATE TABLE IF NOT EXISTS calls(id TEXT PRIMARY KEY, app INTEGER, function TEXT, expires INTEGER, outcome TEXT)",
    [],
  )
  result->Result.map(_ => ())
}

let recorded = async (~execute, record) => {
  let result = await run(
    ~execute,
    "INSERT INTO calls(id, app, function, expires, outcome) VALUES (?, ?, ?, ?, ?)",
    [text(record.id), integer(record.app), text(record.function), integer(record.expires), null],
  )
  result->Result.map(_ => ())
}

let told = async (~execute, ~id, ~outcome) => {
  let result = await run(
    ~execute,
    "UPDATE calls SET outcome = ? WHERE id = ?",
    [text(outcome), text(id)],
  )
  result->Result.map(_ => ())
}

let valueText = json => json->string("name") == Some("text") ? json->string("value") : None

let valueInteger = json =>
  json->string("name") == Some("integer")
    ? json->field("value")->Option.flatMap(JSON.Decode.float)
    : None

let row = json => {
  switch json->JSON.Decode.array {
  | Some([id, app, function, expires, outcome]) =>
    let outcome = switch outcome->string("name") {
    | Some("null") => Some(None)
    | Some("text") => outcome->string("value")->Option.map(value => Some(value))
    | Some(_) | None => None
    }
    switch (valueText(id), valueInteger(app), valueText(function), valueInteger(expires), outcome) {
    | (Some(id), Some(app), Some(function), Some(expires), Some(outcome)) =>
      Ok({id, app, function, expires, outcome})
    | _ => Error(invalid)
    }
  | Some(_) | None => Error(invalid)
  }
}

let found = async (~execute, ~id) => {
  switch await run(
    ~execute,
    "SELECT id, app, function, expires, outcome FROM calls WHERE id = ?",
    [text(id)],
  ) {
  | Error(reason) => Error(reason)
  | Ok(result) =>
    switch result->field("rows")->Option.flatMap(JSON.Decode.array) {
    | Some([]) => Ok(None)
    | Some([record]) => row(record)->Result.map(record => Some(record))
    | Some(_) | None => Error(invalid)
    }
  }
}
