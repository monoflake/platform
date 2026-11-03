let greeting = stamp => `reference ${stamp}\n`

let unreached = (Reach.Unreached(kind)) =>
  Web.response(`no binding reaches ${kind}, RFC rt6gi`, {status: 501})

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

let objectTable = "reference_objects"

/** The batch recording a name against its object, its table made where none is. */
let recording = (name, object) =>
  execute([
    statement(
      `CREATE TABLE IF NOT EXISTS ${objectTable} (object_name TEXT PRIMARY KEY, object TEXT NOT NULL)`,
      [],
    ),
    statement(
      `INSERT OR REPLACE INTO ${objectTable} (object_name, object) VALUES (?, ?)`,
      [text(name), text(object)],
    ),
  ])

let finding = name =>
  execute([statement(`SELECT object FROM ${objectTable} WHERE object_name = ?`, [text(name)])])

let objectOf = (written: JSON.t) =>
  written
  ->JSON.Decode.object
  ->Option.flatMap(o => o->Dict.get("object"))
  ->Option.flatMap(JSON.Decode.string)

let refused = (error, fallback) =>
  Web.response(error->JsExn.message->Option.getOr(fallback), {status: 500})

/** An object's extension, the name's suffix after its last dot, `txt` where there is none. */
let extensionOf = name =>
  switch name->String.lastIndexOf(".") {
  | -1 => "txt"
  | at if at == name->String.length - 1 => "txt"
  | at => name->String.slice(~start=at + 1, ~end=name->String.length)
  }

/** The names one page of a listing holds, and the cursor of the next page where there is one. */
let listed = (page: JSON.t) => {
  let fields = page->JSON.Decode.object->Option.getOr(Dict.make())
  let names =
    fields
    ->Dict.get("objects")
    ->Option.flatMap(JSON.Decode.array)
    ->Option.getOr([])
    ->Array.filterMap(entry => objectOf(entry))
  (names, fields->Dict.get("next")->Option.flatMap(JSON.Decode.string))
}

/** Every object the bucket holds, one name a line, each page read in turn. */
let listing = async env =>
  switch env->Reach.objects {
  | Error(reached) => unreached(reached)
  | Ok(objects) =>
    let rec pages = async (after, names) =>
      switch await objects.list(after, None) {
      | page =>
        switch listed(page) {
        | (more, Some(next)) => await pages(Some(next), names->Array.concat(more))
        | (more, None) => Ok(names->Array.concat(more))
        }
      | exception JsExn(error) => Error(error)
      }
    switch await pages(None, []) {
    | Ok(names) =>
      Web.response(names->Array.map(name => `${name}\n`)->Array.join(""), {status: 200})
    | Error(error) => refused(error, "the bucket refused the call")
    }
  }

/** An object stored under a name or read back by it, the name kept in a row of the database. */
let stored = async (env, ~method, ~name, request) =>
  switch (env->Reach.objects, env->Reach.database) {
  | (Error(reached), _) | (_, Error(reached)) => unreached(reached)
  | (Ok(objects), Ok(database)) =>
    switch method {
    | "PUT" =>
      let body = Uint8Array.fromBuffer(await request->Web.arrayBuffer)
      switch await objects.write(body, extensionOf(name)) {
      | exception JsExn(error) => refused(error, "the bucket refused the call")
      | written =>
        switch objectOf(written) {
        | None => Web.response("the bucket named no object", {status: 500})
        | Some(object) =>
          await called(database, recording(name, object), _ =>
            Web.response(`stored ${object}`, {status: 200})
          )
        }
      }
    | _ =>
      switch await database.execute(finding(name)) {
      | exception JsExn(error) => refused(error, "the database refused the call")
      | executed =>
        switch bodyOf(executed) {
        | None => Web.response("not found", {status: 404})
        | Some(object) =>
          switch await objects.read(object, None) {
          | exception JsExn(error) => refused(error, "the bucket refused the call")
          | content => Web.bytes(content, {status: 200})
          }
        }
      }
    }
  }

let fetch = async (~stamp, ~env, request) => {
  let path = request->Web.address->Web.url->Web.pathname
  let method = request->Web.method
  switch (method, path->String.split("/")) {
  | ("GET", ["", ""]) => Web.response(greeting(stamp), {status: 200})
  | ("PUT" | "GET", ["", "row", key]) if key != "" => await row(env, ~method, ~key, request)
  | ("PUT" | "GET", ["", "object", name]) if name != "" =>
    await stored(env, ~method, ~name, request)
  | ("GET", ["", "objects"]) => await listing(env)
  | _ => Web.response("not found", {status: 404})
  }
}
