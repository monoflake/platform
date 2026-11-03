open Node

let named = "0000002a.babcdef01"
let request = (~method="GET", ~headers=dict{}, ~body=?, ()) =>
  Node.request("http://compute/a%20path/run?x=one&x=two", {method, headers, ?body})

let fetched = async (request, env) => {
  let response = await Worker.fetch(request, env)
  (response->status, await response->text)
}

testAsync("target reads app and binding ids and refuses every other form", async () => {
  deepEqual(Worker.target(named), Some((42., 2882400001.)))
  deepEqual(Worker.target("ffffffff.b00000001"), Some((4294967295., 1.)))
  let malformed = [
    "",
    "0000002a",
    "0000002a.babcdef0",
    "0000002a.babcdef012",
    "0000002A.babcdef01",
    "0000002a.bABCDEF01",
    "00000000.babcdef01",
    "0000002a.b00000000",
    "0000002g.babcdef01",
    "0000002a.babcdef01.extra",
    "0000002a.babcdef01\n",
    "0000002a.babcdef01.b00000001",
  ]
  deepEqual(malformed->Array.map(Worker.target), malformed->Array.map(_ => None))
})

testAsync("passed preserves the call and returns the entry answer unchanged", async () => {
  let entry = Origin.make()
  try {
    let response = await Worker.passed(
      request(
        ~method="PATCH",
        ~headers=dict{
          "target": named,
          "host": "compute",
          "x-forwarded-host": "old",
          "content-type": "application/octet-stream",
          "other": "kept",
        },
        ~body="body\u0000bytes",
        (),
      ),
      ~entry="http://entry:8080",
      ~app=42.,
      ~binding=2882400001.,
    )
    deepEqual(response, entry.answer)
    deepEqual(entry.sent->Array.length, 1)
    let sent = entry.sent->Array.getUnsafe(0)
    deepEqual(sent->url, "http://entry:8080/a%20path/run?x=one&x=two")
    deepEqual(sent->method_, "PATCH")
    deepEqual(await sent->requestText, "body\u0000bytes")
    let headers = sent->headers
    deepEqual(headers->Web.header("host")->Nullable.toOption, Some(named))
    deepEqual(headers->Web.header("x-forwarded-host")->Nullable.toOption, Some(named))
    deepEqual(headers->Web.header("target")->Nullable.toOption, None)
    deepEqual(headers->Web.header("other")->Nullable.toOption, Some("kept"))
    deepEqual(
      headers->Web.header("content-type")->Nullable.toOption,
      Some("application/octet-stream"),
    )
  } catch {
  | error =>
    entry.restore()
    throw(error)
  }
  entry.restore()
})

let configured = records => {
  let env: Worker.env = {
    entry: "http://entry",
    records: records.Records.binding,
    life: "60000",
    deadline: "2",
    retention: "86400000",
  }
  env
}
let appRequest = () => request(~headers=dict{"target": named, "Call": "caller-forged"}, ())
let body = async response => JSON.parseOrThrow(await response->text)
let value = (json, key) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(key))
let outcome = records =>
  records.Records.rows->Dict.toArray->Array.map(((_, row)) => row.Calls.outcome)
let using = async (entry, run) => {
  try {await run()} catch {
  | error =>
    entry.Origin.restore()
    throw(error)
  }
  entry.restore()
}

testAsync(
  "fetch requires every binding, and a bound given must be a positive integer",
  async () => {
    let env = configured(Records.make())
    let invalid: array<Worker.env> = [
      {},
      {...env, entry: ?None},
      {...env, records: ?None},
      {...env, life: "0"},
      {...env, deadline: "-1"},
      {...env, retention: "1.5"},
      {...env, life: "NaN"},
      {...env, deadline: "1ms"},
      {...env, retention: ""},
    ]
    for index in 0 to invalid->Array.length - 1 {
      deepEqual((await Worker.fetch(appRequest(), invalid->Array.getUnsafe(index)))->status, 500)
    }
    deepEqual((await Worker.fetch(request(), env))->status, 400)
    deepEqual((await Worker.fetch(request(~headers=dict{"target": "bad"}, ()), env))->status, 400)
  },
)

testAsync("fetch replaces caller Call and records and tells a 200 success", async () => {
  let records = Records.make()
  let entry = Origin.make(~status=200, ())
  await using(entry, async () => {
    let answer = await Worker.default.fetch(appRequest(), configured(records))
    deepEqual(answer->status, 200)
    deepEqual(await answer->text, "app answer")
    deepEqual(entry.sent->Array.length, 1)
    let id =
      entry.sent
      ->Array.getUnsafe(0)
      ->headers
      ->Web.header("Call")
      ->Nullable.toOption
      ->Option.getOr("")
    deepEqual(id == "caller-forged", false)
    deepEqual(Calls.issuedAt(id)->Option.isSome, true)
    deepEqual(records.rows->Dict.get(id)->Option.map(row => row.outcome), Some(Some("success")))
    deepEqual(records.statements->Array.length, 3)
  })
})

testAsync("fetch reads JSON failure from a clone and tells rejected", async () => {
  let records = Records.make()
  let content = `{"Error":{"failure":"rejected","reason":"conflict"}}`
  let entry = Origin.make(
    ~status=409,
    ~body=content,
    ~headers=dict{"content-type": "application/json; charset=utf-8"},
    (),
  )
  await using(entry, async () => {
    let answer = await Worker.fetch(appRequest(), configured(records))
    deepEqual(answer->status, 409)
    deepEqual(await answer->text, content)
    deepEqual(outcome(records), [Some("rejected")])
  })
})

testAsync("fetch looks up a thrown fetch to unknown through env DEADLINE", async () => {
  let records = Records.make()
  let entry = Origin.make(~fails=true, ())
  await using(entry, async () => {
    let answer = await Worker.fetch(appRequest(), configured(records))
    deepEqual(answer->status, 503)
    let error = (await body(answer))->value("Error")->Option.getOr(JSON.Null)
    deepEqual(error->value("failure"), Some(JSON.String("unknown")))
    let id =
      entry.sent
      ->Array.getUnsafe(0)
      ->headers
      ->Web.header("Call")
      ->Nullable.toOption
      ->Option.getOr("")
    deepEqual(answer->answerHeaders->Web.header("Call")->Nullable.toOption, Some(id))
    deepEqual(outcome(records), [Some("unknown")])
  })
})

testAsync("fetch does not send when records refuses creation or insertion", async () => {
  for index in 0 to 1 {
    let records = Records.make(~refuse=index == 0 ? "CREATE" : "INSERT", ())
    let entry = Origin.make()
    await using(entry, async () => {
      let answer = await Worker.fetch(appRequest(), configured(records))
      deepEqual(answer->status, 503)
      deepEqual(
        (await body(answer))->value("Error")->Option.flatMap(error => error->value("failure")),
        Some(JSON.String("unavailable")),
      )
      deepEqual(entry.sent->Array.length, 0)
    })
  }
})

let statusRequest = id =>
  Node.request(
    "http://compute/compute/status",
    {
      method: "POST",
      headers: dict{"content-type": "application/json"},
      body: JSON.stringify(JSON.Object(dict{"id": JSON.String(id)})),
    },
  )

testAsync("status finds a recorded outcome and reports an unrecorded id", async () => {
  let records = Records.make()
  let entry = Origin.make(~status=200, ())
  await using(entry, async () => {
    let _ = await Worker.fetch(appRequest(), configured(records))
    let id = records.rows->Dict.keysToArray->Array.getUnsafe(0)
    let answer = await Worker.fetch(statusRequest(id), configured(records))
    deepEqual(answer->status, 200)
    let known = (await body(answer))->value("Ok")->Option.getOr(JSON.Null)
    deepEqual(known->value("id"), Some(JSON.String(id)))
    deepEqual(known->value("outcome"), Some(JSON.String("success")))
    deepEqual(known->value("committed"), Some(JSON.Array([])))
    let unknown = Calls.issued(Calls.issuer(), ~now=Web.now() +. 1.)->Option.getOr("")
    let answer = await Worker.fetch(statusRequest(unknown), configured(records))
    deepEqual(answer->status, 200)
    deepEqual(
      (await body(answer))->value("Error")->Option.flatMap(error => error->value("reason")),
      Some(JSON.String("not_found")),
    )
    deepEqual(entry.sent->Array.length, 1)
    deepEqual(records.rows->Dict.keysToArray->Array.length, 1)
  })
})

testAsync("response Call replaces an app header and preserves status and body", async () => {
  let id = Calls.issued(Calls.issuer(), ~now=Web.now())->Option.getOr("")
  let original = Web.response(`{"kept":true}`, {status: 201, headers: dict{"Call": "app-forged"}})
  let answer = Web.withCall(original, id)
  deepEqual(answer->Web.responseHeaders->Web.header("Call")->Nullable.toOption, Some(id))
  deepEqual(
    original->Web.responseHeaders->Web.header("Call")->Nullable.toOption,
    Some("app-forged"),
  )
  deepEqual(answer->Web.status, 201)
  deepEqual(await answer->Web.responseJson, JSON.Object(dict{"kept": JSON.Boolean(true)}))
})

testAsync("fetch tells unavailable after an unheard call expires before DEADLINE", async () => {
  let records = Records.make()
  let entry = Origin.make(~fails=true, ())
  await using(entry, async () => {
    let env = {...configured(records), life: "1", deadline: "50"}
    let answer = await Worker.fetch(appRequest(), env)
    deepEqual(answer->status, 503)
    deepEqual(
      (await body(answer))->value("Error")->Option.flatMap(error => error->value("failure")),
      Some(JSON.String("unavailable")),
    )
    deepEqual(outcome(records), [Some("unavailable")])
  })
})
