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

testAsync("fetch refuses an absent or malformed target before checking ENTRY", async () => {
  deepEqual(await fetched(request(), {}), (400, "the call names no target"))
  deepEqual(
    await fetched(request(~headers=dict{"target": "bad"}, ()), {entry: "http://entry"}),
    (400, "the call names no target"),
  )
  deepEqual(
    await fetched(request(~headers=dict{"target": named}, ()), {}),
    (500, "compute has no ENTRY"),
  )
})

testAsync("fetch passes a target to its app and reports an unanswered app", async () => {
  let entry = Origin.make()
  try {
    deepEqual(
      await Worker.default.fetch(
        request(~headers=dict{"target": named}, ()),
        {entry: "http://entry"},
      ),
      entry.answer,
    )
  } catch {
  | error =>
    entry.restore()
    throw(error)
  }
  entry.restore()
  let entry = Origin.make(~fails=true, ())
  try {
    deepEqual(
      await fetched(request(~headers=dict{"target": named}, ()), {entry: "http://entry"}),
      (503, "the host running app 0000002a did not answer, entry unavailable"),
    )
  } catch {
  | error =>
    entry.restore()
    throw(error)
  }
  entry.restore()
})
