let greeting = stamp => `reference ${stamp}\n`

let unreached = (Reach.Unreached(kind)) =>
  Web.response(`no binding reaches ${kind}, RFC dg903's question 3`, {status: 501})

let table = "reference_rows"

let text = value => JSON.Object(dict{"kind": JSON.String("text"), "value": JSON.String(value)})

let statement = (sql, parameters) => JSON.Object(
  dict{"sql": JSON.String(sql), "parameters": JSON.Array(parameters)},
)

let execute = statements => JSON.Object(dict{"statements": JSON.Array(statements)})

/** The batch writing a row, its table made where none is and a row of that key replaced. */
let writing = (key, body) =>
  execute([
    statement(
      `CREATE TABLE IF NOT EXISTS ${table} (row_key TEXT PRIMARY KEY, row_body TEXT NOT NULL)`,
      [],
    ),
    statement(
      `INSERT OR REPLACE INTO ${table} (row_key, row_body) VALUES (?, ?)`,
      [text(key), text(body)],
    ),
  ])

let reading = key =>
  execute([statement(`SELECT row_body FROM ${table} WHERE row_key = ?`, [text(key)])])

/** The body of the first row the first statement answered, or none where it answered no row. */
let bodyOf = (executed: JSON.t) =>
  executed
  ->JSON.Decode.object
  ->Option.flatMap(o => o->Dict.get("results"))
  ->Option.flatMap(JSON.Decode.array)
  ->Option.flatMap(results => results->Array.get(0))
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(result => result->Dict.get("rows"))
  ->Option.flatMap(JSON.Decode.array)
  ->Option.flatMap(rows => rows->Array.get(0))
  ->Option.flatMap(JSON.Decode.array)
  ->Option.flatMap(row => row->Array.get(0))
  ->Option.flatMap(JSON.Decode.object)
  ->Option.flatMap(value => value->Dict.get("value"))
  ->Option.flatMap(JSON.Decode.string)

/** The call answered, or the contract's reason a refused one threw, as a 500. */
let called = async (database: Reach.database, input, answer) =>
  switch await database.execute(input) {
  | executed => answer(executed)
  | exception JsExn(error) =>
    Web.response(error->JsExn.message->Option.getOr("the database refused the call"), {status: 500})
  }

let row = async (env, ~method, ~key, request) =>
  switch env->Reach.database {
  | Error(reached) => unreached(reached)
  | Ok(database) =>
    switch method {
    | "PUT" =>
      let body = await request->Web.text
      await called(database, writing(key, body), _ => Web.response("written", {status: 200}))
    | _ =>
      await called(database, reading(key), executed =>
        switch bodyOf(executed) {
        | Some(body) => Web.response(body, {status: 200})
        | None => Web.response("not found", {status: 404})
        }
      )
    }
  }

let fetch = async (~stamp, ~env, request) => {
  let path = request->Web.address->Web.url->Web.pathname
  let method = request->Web.method
  switch (method, path->String.split("/")) {
  | ("GET", ["", ""]) => Web.response(greeting(stamp), {status: 200})
  | ("PUT" | "GET", ["", "row", key]) if key != "" => await row(env, ~method, ~key, request)
  | ("PUT" | "GET", ["", "object", name]) if name != "" => unreached(Reach.object())
  | _ => Web.response("not found", {status: 404})
  }
}
