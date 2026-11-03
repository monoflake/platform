open Node

let nowhere: Reach.env = {}

test("the plain Worker answers the fixed text and supplied build stamp", async () => {
  let answer = await Handler.fetch(
    ~stamp="build",
    ~env=nowhere,
    request("https://reference.invalid/", {method: "GET"}),
  )
  equal(status(answer), 200)
  equal(await text(answer), "reference build\n")
})

["GET", "PUT"]->Array.forEach(method =>
  test(`${method} object fails with the reach where the deploy filled no bucket`, async () => {
    let answer = await Handler.fetch(
      ~stamp="build",
      ~env=nowhere,
      request("https://reference.invalid/object/key", {method: method}),
    )
    equal(status(answer), 501)
    equal(await text(answer), "no binding reaches object, RFC rt6gi")
  })
)

["GET", "PUT"]->Array.forEach(method =>
  test(`${method} row fails with the reach where the deploy filled no database`, async () => {
    let answer = await Handler.fetch(
      ~stamp="build",
      ~env=nowhere,
      request("https://reference.invalid/row/key", {method: method}),
    )
    equal(status(answer), 501)
    equal(await text(answer), "no binding reaches database, RFC rt6gi")
  })
)

test("unknown routes and methods answer 404", async () => {
  (
    await Promise.all(
      ["/row/", "/object/", "/row/key/extra", "/missing"]->Array.map(async path => {
        let answer = await Handler.fetch(
          ~stamp="build",
          ~env=nowhere,
          request(`https://reference.invalid${path}`, {method: "GET"}),
        )
        equal(status(answer), 404)
      }),
    )
  )->ignore
  let answer = await Handler.fetch(
    ~stamp="build",
    ~env=nowhere,
    request("https://reference.invalid/row/key", {method: "DELETE"}),
  )
  equal(status(answer), 404)
})

/** A fake `env.database` keeping the calls made and answering from what the batches asked. */
let database = (~refuse=?) => {
  let calls = []
  let rows = Dict.make()
  let objects = Dict.make()
  let execute = async input => {
    calls->Array.push(input)
    switch refuse {
    | Some(reason) => JsError.throwWithMessage(reason)
    | None => ()
    }
    let statements =
      input
      ->JSON.Decode.object
      ->Option.flatMap(o => o->Dict.get("statements"))
      ->Option.flatMap(JSON.Decode.array)
      ->Option.getOr([])
    let results = statements->Array.map(statement => {
      let o = statement->JSON.Decode.object->Option.getOr(Dict.make())
      let sql = o->Dict.get("sql")->Option.flatMap(JSON.Decode.string)->Option.getOr("")
      let parameters =
        o
        ->Dict.get("parameters")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.map(p =>
          p
          ->JSON.Decode.object
          ->Option.flatMap(p => p->Dict.get("value"))
          ->Option.flatMap(JSON.Decode.string)
          ->Option.getOr("")
        )
      let rows = sql->String.includes("reference_objects") ? objects : rows
      let found = if sql->String.startsWith("INSERT OR REPLACE") {
        rows->Dict.set(parameters->Array.getUnsafe(0), parameters->Array.getUnsafe(1))
        []
      } else if sql->String.startsWith("SELECT") {
        switch rows->Dict.get(parameters->Array.getUnsafe(0)) {
        | Some(body) => [
            [JSON.parseOrThrow(`{"kind":"text","value":${JSON.stringify(JSON.String(body))}}`)],
          ]
        | None => []
        }
      } else {
        []
      }
      JSON.Object(
        dict{
          "columns": JSON.Array([]),
          "rows": JSON.Array(found->Array.map(row => JSON.Array(row))),
          "changed": JSON.Number(0.),
        },
      )
    })
    JSON.Object(dict{"results": JSON.Array(results)})
  }
  (({execute: execute}: Reach.database), calls)
}

let sent = (env, method, key, ~body=?) =>
  Handler.fetch(
    ~stamp="build",
    ~env,
    request(`https://reference.invalid/row/${key}`, {method, ?body}),
  )

test("a row is written in one batch, its table made and a row of that key replaced", async () => {
  let (fake, calls) = database()
  let env: Reach.env = {database: fake}
  let answer = await sent(env, "PUT", "reference", ~body="row run\n")
  equal(status(answer), 200)
  equal(calls->Array.length, 1)
  let statements =
    calls
    ->Array.getUnsafe(0)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("statements"))
    ->Option.flatMap(JSON.Decode.array)
    ->Option.getOr([])
  equal(statements->Array.length, 2)
  equal(
    JSON.stringify(statements->Array.getUnsafe(1)),
    `{"sql":"INSERT OR REPLACE INTO reference_rows (row_key, row_body) VALUES (?, ?)","parameters":[{"kind":"text","value":"reference"},{"kind":"text","value":"row run\\n"}]}`,
  )
  equal(
    statements
    ->Array.getUnsafe(0)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("sql"))
    ->Option.flatMap(JSON.Decode.string),
    Some(
      "CREATE TABLE IF NOT EXISTS reference_rows (row_key TEXT PRIMARY KEY, row_body TEXT NOT NULL)",
    ),
  )
})

test(
  "a row written is read back as it was, replaced by a second write, 404 where none",
  async () => {
    let (fake, _) = database()
    let env: Reach.env = {database: fake}
    equal(status(await sent(env, "GET", "reference")), 404)
    ignore(await sent(env, "PUT", "reference", ~body="first"))
    let first = await sent(env, "GET", "reference")
    equal(status(first), 200)
    equal(await text(first), "first")
    ignore(await sent(env, "PUT", "reference", ~body="second"))
    equal(await text(await sent(env, "GET", "reference")), "second")
    equal(status(await sent(env, "GET", "other")), 404)
  },
)

test("a call the database refuses answers 500 with the reason in its message", async () => {
  let (fake, _) = database(~refuse="read_only")
  let env: Reach.env = {database: fake}
  let written = await sent(env, "PUT", "reference", ~body="row")
  equal(status(written), 500)
  equal(await text(written), "read_only")
  let read = await sent(env, "GET", "reference")
  equal(status(read), 500)
  equal(await text(read), "read_only")
})

test(
  "the build declares a database slot, an object bucket slot and one effect function beside its ingress",
  async () => {
    equal(
      JSON.parseOrThrow(readFileSync("metadata.json", "utf8")),
      JSON.parseOrThrow(`{"ingress":[{"name":"binding"}],"slots":[{"name":"database","type":"database"},{"name":"objects","type":"object_bucket"}],"functions":[{"name":"fetch","kind":"effect"}]}`),
    )
  },
)

/** A fake `env.objects` keeping the calls made. */
let bucket = (~refuse=?) => {
  let calls = []
  let held = Dict.make()
  let write = async (content, extension) => {
    calls->Array.push(`write ${extension}`)
    switch refuse {
    | Some(reason) => JsError.throwWithMessage(reason)
    | None => ()
    }
    let object = `h${Int.toString(content->String.length)}${content->String.slice(
        ~start=0,
        ~end=3,
      )}.${extension}`
    held->Dict.set(object, content)
    JSON.Object(dict{"object": JSON.String(object), "size": JSON.Number(0.)})
  }
  let read = async (object, _range) => {
    calls->Array.push(`read ${object}`)
    switch held->Dict.get(object) {
    | Some(content) => encode(textEncoder(), content)
    | None => JsError.throwWithMessage("not_found")
    }
  }
  let unused = async _ => JSON.Null
  let listing = async (_, _) => JSON.Null
  (({write, read, describe: unused, list: listing, delete: unused}: Reach.objects), calls)
}

let stowed = (env, method, name, ~body=?) =>
  Handler.fetch(
    ~stamp="build",
    ~env,
    request(`https://reference.invalid/object/${name}`, {method, ?body}),
  )

test("an object is written as txt and its name recorded against the object it made", async () => {
  let (fakeDatabase, databaseCalls) = database()
  let (fakeBucket, bucketCalls) = bucket()
  let env: Reach.env = {database: fakeDatabase, objects: fakeBucket}
  let answer = await stowed(env, "PUT", "reference", ~body="object run\n")
  equal(status(answer), 200)
  equal(bucketCalls, ["write txt"])
  equal(databaseCalls->Array.length, 1)
  let statements =
    databaseCalls
    ->Array.getUnsafe(0)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("statements"))
    ->Option.flatMap(JSON.Decode.array)
    ->Option.getOr([])
  equal(statements->Array.length, 2)
  equal(
    statements
    ->Array.getUnsafe(0)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("sql"))
    ->Option.flatMap(JSON.Decode.string),
    Some(
      "CREATE TABLE IF NOT EXISTS reference_objects (object_name TEXT PRIMARY KEY, object TEXT NOT NULL)",
    ),
  )
  equal(
    JSON.stringify(statements->Array.getUnsafe(1)),
    `{"sql":"INSERT OR REPLACE INTO reference_objects (object_name, object) VALUES (?, ?)","parameters":[{"kind":"text","value":"reference"},{"kind":"text","value":"h11obj.txt"}]}`,
  )
})

test("an object written is read back by its name, replaced by a second write", async () => {
  let (fakeDatabase, _) = database()
  let (fakeBucket, _) = bucket()
  let env: Reach.env = {database: fakeDatabase, objects: fakeBucket}
  ignore(await stowed(env, "PUT", "reference", ~body="first"))
  let first = await stowed(env, "GET", "reference")
  equal(status(first), 200)
  equal(await text(first), "first")
  ignore(await stowed(env, "PUT", "reference", ~body="second"))
  equal(await text(await stowed(env, "GET", "reference")), "second")
})

test("an object and a row of one name do not meet", async () => {
  let (fakeDatabase, _) = database()
  let (fakeBucket, _) = bucket()
  let env: Reach.env = {database: fakeDatabase, objects: fakeBucket}
  ignore(await sent(env, "PUT", "reference", ~body="row"))
  equal(status(await stowed(env, "GET", "reference")), 404)
})

test("an unknown object name answers 404 without reading the bucket", async () => {
  let (fakeDatabase, _) = database()
  let (fakeBucket, bucketCalls) = bucket()
  let env: Reach.env = {database: fakeDatabase, objects: fakeBucket}
  equal(status(await stowed(env, "GET", "missing")), 404)
  equal(bucketCalls, [])
})

test("a bucket that refuses answers 500 with the reason, and no row is recorded", async () => {
  let (fakeDatabase, databaseCalls) = database()
  let (fakeBucket, _) = bucket(~refuse="storage_full")
  let env: Reach.env = {database: fakeDatabase, objects: fakeBucket}
  let answer = await stowed(env, "PUT", "reference", ~body="x")
  equal(status(answer), 500)
  equal(await text(answer), "storage_full")
  equal(databaseCalls->Array.length, 0)
})

test("an object route with a database but no bucket answers 501 citing the reach", async () => {
  let (fakeDatabase, _) = database()
  let env: Reach.env = {database: fakeDatabase}
  let answer = await stowed(env, "PUT", "reference", ~body="x")
  equal(status(answer), 501)
  equal(await text(answer), "no binding reaches object, RFC rt6gi")
})
