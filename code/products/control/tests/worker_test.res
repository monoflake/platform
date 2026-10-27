open Node

let request = (~method="GET", path, ~headers=dict{}, ~body=?) =>
  Web.request(`https://control.example.com${path}`, {method, headers, ?body})

let configured = () => {
  let host = Host.make()
  let database = Sqlite.database()
  let bucket = Routes.bucket()
  let env: Stores.env = {
    state: database,
    artifacts: bucket,
    hosts: Routes.fetcher(host.reach.fetch),
    operator: "operator",
    sealingKey: Envelope.Base64url.encode(Web.random(32)),
  }
  (env, database, bucket, host)
}

test(
  "the bundled control exports fetch and answers calls, artifacts, relay and objects",
  async () => {
    let worker = await Workerd.bundled()
    deepEqual((await worker.fetch(request("/"), {}))->Web.status, 404)
    let (env, database, bucket, host) = configured()
    let answer = await worker.fetch(
      request(
        ~method="POST",
        "/organizations/open",
        ~headers=dict{"authorization": "Bearer operator", "content-type": "application/json"},
        ~body=Web.utf8(
          JSON.stringify(
            Envelope.Contracts.Interface.Organizations.toJson({
              call: Open({label: "first"}),
              capabilities: [],
            }),
          ),
        ),
      ),
      env,
    )
    deepEqual(answer->Web.status, 200)
    let hash = String.repeat("ab", 32)
    await bucket->Stores.put(hash, Web.utf8("artifact"))
    let artifact = await worker.fetch(request(`/artifacts/${hash}`), env)
    deepEqual((artifact->Web.status, await artifact->Web.text), (200, "artifact"))
    let state = State.ofDatabase(database, ~sealing=Sealing.ofKey(env.sealingKey))
    let secret = Uint8Array.fromLength(32)
    let {id: organization} = await state.openOrganization("relay", ~secret)
    let storage = await state.openBinding(~organization, ~secret, ~relayed=false, ~random=() =>
      16777218.
    )
    let relayed = await state.openBinding(~organization, ~secret, ~relayed=true, ~random=() =>
      16777219.
    )
    ignore(await state.addressed(~binding=storage, ~address="10.200.0.1"))
    ignore(await state.addressed(~binding=relayed, ~address="10.200.0.2"))
    await state.routed(~binding=storage)
    await state.routed(~binding=relayed)
    let token = `Bearer ${Access.organizationText(organization, secret)}`
    let relay = await worker.fetch(
      request("/relay/10.200.0.2/36879/hello?x=1", ~headers=dict{"proxy-authorization": token}),
      env,
    )
    let object = await worker.fetch(
      request(
        ~method="POST",
        "/object/read",
        ~headers=dict{"authorization": token},
        ~body=Web.utf8("{}"),
      ),
      env,
    )
    deepEqual((relay->Web.status, object->Web.status), (200, 200))
    deepEqual(
      host.seen->Array.map(s => s.url),
      ["http://10.200.0.2:36879/hello?x=1", "http://10.200.0.1:37483/object/read"],
    )
  },
)

test("only the four interfaces' declared operations accept POST paths", async () => {
  let (env, _, _, _) = configured()
  let interfaces =
    JSON.parseOrThrow(readText(fromRoot("model/contracts.json")))
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("interfaces"))
    ->Option.flatMap(JSON.Decode.object)
    ->Option.getOrThrow
  let paths = ["organizations", "bindings", "reaches", "releases"]->Array.flatMap(name =>
    interfaces
    ->Dict.getUnsafe(name)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("operations"))
    ->Option.flatMap(JSON.Decode.array)
    ->Option.getOrThrow
    ->Array.map(
      op => {
        let operation =
          op
          ->JSON.Decode.object
          ->Option.getOrThrow
          ->Dict.getUnsafe("name")
          ->JSON.Decode.string
          ->Option.getOrThrow
        `/${name}/${operation}`
      },
    )
  )
  deepEqual(paths->Array.length, 9)
  for i in 0 to paths->Array.length - 1 {
    let path = paths->Array.getUnsafe(i)
    let answer = await Worker.default.fetch(request(~method="POST", path), env)
    deepEqual(answer->Web.status, 400, ~message=path)
    let wrongMethod = await Worker.default.fetch(request(path), env)
    deepEqual(wrongMethod->Web.status, 404, ~message=path)
  }
})

test("mounts, root, unknown operations and malformed artifact paths answer 404", async () => {
  let (env, _, _, _) = configured()
  let paths = [
    "/v1/01000004/",
    "/",
    "/organizations/unknown",
    "/management/describe",
    "/releases/deploy/extra",
    "/releases/deploy/",
    "/artifacts/aa",
    `/artifacts/${String.repeat("a", 63)}g`,
    "/object/read/extra",
  ]
  for i in 0 to paths->Array.length - 1 {
    let path = paths->Array.getUnsafe(i)
    for j in 0 to 1 {
      let method = j == 0 ? "GET" : "POST"
      deepEqual(
        (await Worker.default.fetch(request(~method, path), env))->Web.status,
        404,
        ~message=path,
      )
      deepEqual(
        (await Worker.default.fetch(request(~method, path), {}))->Web.status,
        404,
        ~message=path,
      )
    }
  }
  deepEqual(
    (
      await Worker.default.fetch(
        request(~method="POST", `/artifacts/${String.repeat("ab", 32)}`),
        env,
      )
    )->Web.status,
    404,
  )
})

test("a control standing on another still gives neither relay nor objects", async () => {
  let env: Stores.env = {standsOn: "https://control.example.net", standsOnToken: "token"}
  for i in 0 to 1 {
    let path = i == 0 ? "/relay/10.200.0.1/36879/" : "/object/read"
    deepEqual((await Worker.default.fetch(request(~method="POST", path), env))->Web.status, 404)
  }
})
