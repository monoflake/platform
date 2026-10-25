/*** `Gateway` held to RFCs vr5lw and rxmd9, an app's scope read and dropped, its host named. */
open Node

test("a path under an app's scope hands the app what follows it, its root at least", async () =>
  deepEqual(
    [
      "/v1/0a1b2c3d",
      "/v1/0a1b2c3d/",
      "/v2/fedcba98/a/b",
      "/v1/00000000/",
      "/v1/0A1B2C3D/",
      "/v1/a1b2c3d/",
      "/v1/0a1b2c3d0/",
      "/v1/0a1b2c3dx/",
      "/0a1b2c3d/",
      "/v1/",
      "/organizations/open",
    ]->Array.map(Gateway.routed),
    [
      Some({app: 169552957., path: "/"}),
      Some({app: 169552957., path: "/"}),
      Some({app: 4275878552., path: "/a/b"}),
      None,
      None,
      None,
      None,
      None,
      None,
      None,
      None,
    ],
  )
)

test("an id deployed before hex is still routed by its decimal, to the same app", async () => {
  deepEqual(
    [
      "/v1/app-2",
      "/v1/app-2/",
      "/v1/app-4294967295/a",
      "/v1/app-0/",
      "/v1/app-02/",
      "/v1/app-1x/",
      "/v1/app-4294967296/",
      "/app-2/",
    ]->Array.map(Gateway.routed),
    [
      Some({app: 2., path: "/"}),
      Some({app: 2., path: "/"}),
      Some({app: 4294967295., path: "/a"}),
      None,
      None,
      None,
      None,
      None,
    ],
  )
  deepEqual(Gateway.routed("/v1/app-2/x"), Gateway.routed("/v1/00000002/x"))
})

test(
  "no path of the control's own is read as an app's, every interface's operation among them",
  async () => {
    let contracts = JSON.parseOrThrow(readText(fromRoot("model/contracts.json")))
    let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
    let interfaces =
      contracts->field("interfaces")->Option.flatMap(JSON.Decode.object)->Option.getOr(dict{})
    let operations =
      interfaces
      ->Dict.toArray
      ->Array.flatMap(((name, interface_)) =>
        interface_
        ->field("operations")
        ->Option.flatMap(JSON.Decode.array)
        ->Option.getOr([])
        ->Array.filterMap(op => op->field("name")->Option.flatMap(JSON.Decode.string))
        ->Array.map(op => `/${name}/${op}`)
      )
    ok(operations->Array.includes("/releases/deploy"), ~message="the model's operations were read")
    let paths = [
      ...operations,
      `/artifacts/${String.repeat("ab", 32)}`,
      "/relay/10.200.0.1/36879/",
      "/relay/10.200.0.1/37483/management/describe",
      "/object/read",
      "/",
    ]
    deepEqual(paths->Array.filter(p => Gateway.routed(p) != None), [])
  },
)

test(
  "the entry is asked by the host deploy names, the app in 8 hex digits then the binding's",
  async () => {
    deepEqual(Gateway.host(~app=1., ~binding=3.), "00000001.b00000003")
    deepEqual(Gateway.host(~app=4275878552., ~binding=169552957.), "fedcba98.b0a1b2c3d")
    // An app routed by its decimal is handed on by its hex form all the same.
    deepEqual(
      Gateway.routed("/v1/app-2/")->Option.map(r => Gateway.host(~app=r.app, ~binding=1.)),
      Some("00000002.b00000001"),
    )
  },
)

test(
  "a request passed reaches the binding's entry by its host, and an app not deployed is not",
  async () => {
    let state = Memory.state()
    let host = Host.make()
    let request = Web.request(
      "https://control.test/v1/00000004/hello?x=1",
      {method: "GET", headers: dict{}},
    )
    let unknown = await Gateway.passed(
      state,
      host.reach,
      ~port=36879,
      request,
      {app: 4., path: "/hello"},
      ~search="?x=1",
    )
    deepEqual(unknown->Web.status, 404)
    let {id: organization} = await state.openOrganization(
      "first",
      ~secret=Uint8Array.fromLength(32),
    )
    let binding = await state.openBinding(
      ~organization,
      ~secret=Uint8Array.fromLength(32),
      ~relayed=false,
      ~random=() => 169552957.,
    )
    ignore(await state.addressed(~binding, ~address="10.200.0.1"))
    await state.routed(~binding)
    ignore(await state.drawApp(~random=() => 4.))
    await state.deploy({app: 4., binding, release: "", capacity: 1.})
    let answer = await Gateway.passed(
      state,
      host.reach,
      ~port=36879,
      request,
      {app: 4., path: "/hello"},
      ~search="?x=1",
    )
    deepEqual(await answer->Web.text, "entry asked /hello for 00000004.b0a1b2c3d")
    deepEqual(host.seen->Array.map(s => s.url), ["http://10.200.0.1:36879/hello?x=1"])
    host.gone := true
    let gone = await Gateway.passed(
      state,
      host.reach,
      ~port=36879,
      request,
      {app: 4., path: "/hello"},
      ~search="",
    )
    deepEqual(gone->Web.status, 503)
  },
)

test(
  "a binding kept before ids were drawn is still bound, and served by its hex form",
  async () => {
    let database = Sqlite.database()
    let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
    await run("INSERT INTO organization (id, label) VALUES (2, 'first')")
    await run(
      `INSERT INTO binding (id, organization, secret, address, bound) VALUES (1, 2, '${String.repeat(
          "ab",
          32,
        )}', '10.200.0.1', 1)`,
    )
    await run("INSERT INTO release (hash, form, size) VALUES ('aa', 'modules', 3)")
    await run("INSERT INTO deployment (app, binding, release, capacity) VALUES (4, 1, 'aa', 1)")
    await run("INSERT INTO app (id) VALUES (4)")
    let key = Some(Envelope.Base64url.encode(Uint8Array.fromLength(32)))
    let state = State.ofDatabase(database, ~sealing=Sealing.ofKey(key))
    let host = Host.make()
    let answer = await Gateway.passed(
      state,
      host.reach,
      ~port=36879,
      Web.request("https://control.test/v1/00000004/", {method: "GET", headers: dict{}}),
      {app: 4., path: "/"},
      ~search="",
    )
    // A binding opened after it is drawn, and given the next address free.
    let next = await state.openBinding(
      ~organization=2.,
      ~secret=Uint8Array.fromLength(32),
      ~relayed=false,
      ~random=() => 169552957.,
    )
    deepEqual(
      (
        await answer->Web.text,
        host.seen->Array.map(s => s.url),
        await state.addressed(~binding=1.),
        next,
        await state.addressed(~binding=next),
      ),
      (
        "entry asked / for 00000004.b00000001",
        ["http://10.200.0.1:36879/"],
        Some("10.200.0.1"),
        169552957.,
        Some("10.200.0.2"),
      ),
    )
  },
)

/** A state holding app 4 deployed on a bound binding, its host faked. */
let deployed = async () => {
  let state = Memory.state()
  let {id: organization} = await state.openOrganization("first", ~secret=Uint8Array.fromLength(32))
  let binding = await state.openBinding(
    ~organization,
    ~secret=Uint8Array.fromLength(32),
    ~relayed=false,
    ~random=Memory.counting(),
  )
  ignore(await state.addressed(~binding, ~address="10.200.0.1"))
  await state.routed(~binding)
  ignore(await state.drawApp(~random=() => 4.))
  await state.deploy({app: 4., binding, release: "", capacity: 1.})
  state
}

let passing = (state, host: Host.t, request) =>
  Gateway.passed(state, host.reach, ~port=36879, request, {app: 4., path: "/"}, ~search="")

test(
  "a request with no body that fails before any answer is sent once more, and answered",
  async () => {
    // The entry closes its kept connections as it restarts, which a request sent on one meets.
    let state = await deployed()
    let host = Host.make()
    host.drops := 1
    let asked = Web.request("https://control.test/v1/00000004/", {method: "GET", headers: dict{}})
    let answer = await passing(state, host, asked)
    deepEqual((answer->Web.status, host.seen->Array.length), (200, 2))
    host.drops := 2
    let twice = await passing(state, host, asked)
    deepEqual((twice->Web.status, host.seen->Array.length), (503, 4))
  },
)

test("a request whose body a first send spent is not sent again", async () => {
  let state = await deployed()
  let host = Host.make()
  host.drops := 1
  let posted = Web.request(
    "https://control.test/v1/00000004/",
    {method: "POST", headers: dict{}, body: Web.utf8("once")},
  )
  let answer = await passing(state, host, posted)
  deepEqual((answer->Web.status, host.seen->Array.length), (503, 1))
  let empty = Web.request("https://control.test/v1/00000004/", {method: "POST", headers: dict{}})
  host.drops := 1
  deepEqual((await passing(state, host, empty))->Web.status, 200)
})

test(
  "the hosts' binding is reached as it is given, though every name read on it is present",
  async () => {
    switch Worker.reachOf(Workerd.everyName()) {
    | Some(reach) =>
      let answer = await reach.fetch(
        Web.request("http://10.200.0.1:37483/", {method: "GET", headers: dict{}}),
      )
      deepEqual(await answer->Web.text, "through")
    | None => ok(false, ~message="the binding was not taken")
    }
  },
)

test("an app on a binding reached by its origin is beyond the gateway's host", async () => {
  let state = Memory.state()
  let host = Host.make()
  let secret = Uint8Array.fromLength(32)
  let {id: organization} = await state.openOrganization("first", ~secret)
  let binding = await state.openBinding(
    ~organization,
    ~secret,
    ~relayed=false,
    ~random=Memory.counting(),
  )
  ignore(await state.originated(~binding, ~origin="https://driver.example.com"))
  ignore(await state.drawApp(~random=() => 4.))
  await state.deploy({app: 4., binding, release: "", capacity: 1.})
  let answer = await Gateway.passed(
    state,
    host.reach,
    ~port=36879,
    Web.request("https://control.test/v1/00000004/", {method: "GET", headers: dict{}}),
    {app: 4., path: "/"},
    ~search="",
  )
  let reason =
    JSON.parseOrThrow(await answer->Web.text)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("reason"))
    ->Option.flatMap(JSON.Decode.string)
  deepEqual((answer->Web.status, reason, host.seen), (400, Some("beyond_host"), []))
})
