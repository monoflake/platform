type t = {binding: Worker.records, rows: dict<Calls.record>, statements: array<string>}
let object = fields => JSON.Object(Dict.fromArray(fields))
let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
let text = value => object([("name", JSON.String("text")), ("value", JSON.String(value))])
let integer = value => object([("name", JSON.String("integer")), ("value", JSON.Number(value))])
let empty = JSON.parseOrThrow(`{"columns":[],"rows":[],"changed":0}`)

let make = (~refuse="", ()) => {
  let rows: dict<Calls.record> = dict{}
  let statements = []
  let execute = async input => {
    let statement =
      input
      ->field("statements")
      ->Option.flatMap(JSON.Decode.array)
      ->Option.getOr([])
      ->Array.getUnsafe(0)
    let sql = statement->field("sql")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
    statements->Array.push(sql)
    let parameters =
      statement->field("parameters")->Option.flatMap(JSON.Decode.array)->Option.getOr([])
    let string = index =>
      parameters
      ->Array.getUnsafe(index)
      ->field("value")
      ->Option.flatMap(JSON.Decode.string)
      ->Option.getOr("")
    let number = index =>
      parameters
      ->Array.getUnsafe(index)
      ->field("value")
      ->Option.flatMap(JSON.Decode.float)
      ->Option.getOr(0.)
    if refuse != "" && sql->String.startsWith(refuse) {
      JSON.parseOrThrow(`{"Error":{"reason":"unavailable"}}`)
    } else {
      let result = if sql->String.startsWith("INSERT") {
        rows->Dict.set(
          string(0),
          {
            id: string(0),
            app: number(1),
            function: string(2),
            expires: number(3),
            outcome: None,
          },
        )
        empty
      } else if sql->String.startsWith("UPDATE") {
        rows
        ->Dict.get(string(1))
        ->Option.forEach(row => rows->Dict.set(row.id, {...row, outcome: Some(string(0))}))
        empty
      } else if sql->String.startsWith("SELECT") {
        let found =
          rows
          ->Dict.get(string(0))
          ->Option.map(row => JSON.Array([
            text(row.id),
            integer(row.app),
            text(row.function),
            integer(row.expires),
            row.outcome->Option.map(text)->Option.getOr(object([("name", JSON.String("null"))])),
          ]))
        object([("rows", JSON.Array(found->Option.map(row => [row])->Option.getOr([])))])
      } else {
        empty
      }
      object([("Ok", object([("results", JSON.Array([result]))]))])
    }
  }
  {binding: {execute: execute}, rows, statements}
}
