module Sealing = ControlOrganization.Sealing
module Stores = ControlOrganization.Stores
module State = ControlOrganization.State

/*** `Gateway` held to RFCs vr5lw and rxmd9, an app's scope read and dropped, its host named. */
open Node

let reads = (state: State.t): State.reads => {
  binding: async id =>
    (await state.binding(id))->Option.map((b): State.reached => {
      address: b.address,
      origin: b.origin,
      bound: b.bound,
    }),
  deployment: state.deployment,
  domain: state.domain,
  mount: async (~organization as _, ~scope as _) => None,
}

/** The routing reads holding one mount, each scope asked of it kept in `asked`. */
let holding = (~organization, ~scope, ~app, ~asked=[]): State.reads => {
  binding: async _ => None,
  deployment: async _ => None,
  domain: async _ => None,
  mount: async (~organization as given, ~scope as named) => {
    asked->Array.push(named)
    given == organization && named == scope ? Some(app) : None
  },
}

test("a path under a mount hands the app what follows its scope, its root at least", async () => {
  let reads = holding(~organization=1., ~scope="hello", ~app=16777220.)
  let mounted = path => Gateway.mounted(reads, ~organization=1., path)
  deepEqual(await mounted("/v1/hello"), Some({app: 16777220., path: "/"}))
  deepEqual(await mounted("/v1/hello/"), Some({app: 16777220., path: "/"}))
  deepEqual(await mounted("/v22/hello/a/b"), Some({app: 16777220., path: "/a/b"}))
})

test("only a declared mount is forwarded, an app's id and decimal no way in", async () => {
  let asked = []
  let reads = holding(~organization=1., ~scope="hello", ~app=16777220., ~asked)
  let mounted = (~organization=1., path) => Gateway.mounted(reads, ~organization, path)
  let refused = [
    "/v1/01000004/",
    "/v1/app-2/",
    "/v1/other/",
    "/hello/",
    "/v1/",
    "/v/hello/",
    "/vx/hello/",
    "/v1/Hello/",
    "/v1/-hello/",
    "/v1/hel%6co/",
    "/organizations/open",
  ]
  for i in 0 to refused->Array.length - 1 {
    let path = refused->Array.getUnsafe(i)
    deepEqual(await mounted(path), None, ~message=path)
  }
  // A path no label writes is refused with no read.
  deepEqual(asked, ["01000004", "app-2", "other"])
  deepEqual(await mounted(~organization=2., "/v1/hello/"), None)
})

test(
  "no path of the control's own is read as a mount, every interface's operation among them",
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
    let reads = holding(~organization=1., ~scope="releases", ~app=16777220.)
    for i in 0 to paths->Array.length - 1 {
      let path = paths->Array.getUnsafe(i)
      deepEqual(await Gateway.mounted(reads, ~organization=1., path), None, ~message=path)
    }
  },
)

test(
  "the entry is asked by the host deploy names, the app in 8 hex digits then the binding's",
  async () => {
    deepEqual(Gateway.host(~app=1., ~binding=3.), "00000001.b00000003")
    deepEqual(Gateway.host(~app=4275878552., ~binding=169552957.), "fedcba98.b0a1b2c3d")
  },
)

test(
  "a request passed reaches the binding's entry by its host, and an app not deployed is not",
  async () => {
    let state = Memory.state()
    let host = Host.make()
    let request = Web.request(
      "https://gateway.example.com/v1/01000004/hello?x=1",
      {method: "GET", headers: dict{}},
    )
    let unknown = await Gateway.passed(
      reads(state),
      host.reach,
      ~port=36879,
      request,
      {app: 16777220., path: "/hello"},
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
    ignore(await state.drawApp(~random=() => 16777220.))
    await state.deploy({app: 16777220., binding, release: "", capacity: 1., kind: None})
    let answer = await Gateway.passed(
      reads(state),
      host.reach,
      ~port=36879,
      request,
      {app: 16777220., path: "/hello"},
      ~search="?x=1",
    )
    deepEqual(await answer->Web.text, "entry asked /hello for 01000004.b0a1b2c3d")
    deepEqual(host.seen->Array.map(s => s.url), ["http://10.200.0.1:36879/hello?x=1"])
    host.gone := true
    let gone = await Gateway.passed(
      reads(state),
      host.reach,
      ~port=36879,
      request,
      {app: 16777220., path: "/hello"},
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
      State.readsOfDatabase(database),
      host.reach,
      ~port=36879,
      Web.request("https://gateway.example.com/v1/00000004/", {method: "GET", headers: dict{}}),
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

/** A state holding app 01000004 deployed on a bound binding, its host faked. */
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
  ignore(await state.drawApp(~random=() => 16777220.))
  await state.deploy({app: 16777220., binding, release: "", capacity: 1., kind: None})
  state
}

let passing = (state, host: Host.t, request) =>
  Gateway.passed(
    reads(state),
    host.reach,
    ~port=36879,
    request,
    {app: 16777220., path: "/"},
    ~search="",
  )

test("compute reads only a configured app and binding", async () => {
  deepEqual(Gateway.computed("0a0b0c0d.b00000002"), Some((168496141., 2.)))
  let refused = [
    "",
    "not a host",
    "0A0B0C0D.b00000002",
    "0a0b0c0d.b00000000",
    "0a0b0c0d.b00000002/path",
    "0a0b0c0d.b00000002\n",
  ]
  refused->Array.forEach(text => deepEqual(Gateway.computed(text), None, ~message=text))
})

test("compute receives the whole routed path and the deployed app as target", async () => {
  let state = await deployed()
  let deployment = (await state.deployment(16777220.))->Option.getOrThrow
  let binding = deployment.binding
  let host = Host.make()
  let sent = []
  let reach: ControlOrganization.Reach.t = {
    ...host.reach,
    fetch: async request => {
      let header = name => request->Web.requestHeaders->Web.header(name)->Nullable.toOption
      sent->Array.push((
        header("target"),
        header("x-forwarded-host"),
        request->Web.method_,
        Web.fromUtf8(await request->Web.bytesOf),
      ))
      await host.reach.fetch(request)
    },
  }
  let request = Web.request(
    "https://gateway.example.com/a%2Fb//c?x=%2f&x=+",
    {method: "POST", headers: dict{"target": "untrusted"}, body: Web.utf8("body")},
  )
  let through = routed =>
    Gateway.through(
      reads(state),
      reach,
      ~port=36879,
      request,
      routed,
      ~compute=(168496141., binding),
      ~search="?x=%2f&x=+",
    )
  deepEqual((await through({app: 99., path: "/a%2Fb//c"}))->Web.status, 404)
  deepEqual(host.seen, [])
  let answer = await through({app: 16777220., path: "/a%2Fb//c"})
  deepEqual(answer->Web.status, 200)
  deepEqual(
    host.seen->Array.map(s => (s.url, s.host)),
    [("http://10.200.0.1:36879/a%2Fb//c?x=%2f&x=+", Some(Gateway.host(~app=168496141., ~binding)))],
  )
  deepEqual(
    sent,
    [
      (
        Some(Gateway.host(~app=16777220., ~binding)),
        Some(Gateway.host(~app=168496141., ~binding)),
        "POST",
        "body",
      ),
    ],
  )
})

test(
  "a request with no body that fails before any answer is sent once more, and answered",
  async () => {
    // The entry closes its kept connections as it restarts, which a request sent on one meets.
    let state = await deployed()
    let host = Host.make()
    host.drops := 1
    let asked = Web.request(
      "https://gateway.example.com/v1/01000004/",
      {method: "GET", headers: dict{}},
    )
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
    "https://gateway.example.com/v1/01000004/",
    {method: "POST", headers: dict{}, body: Web.utf8("once")},
  )
  let answer = await passing(state, host, posted)
  deepEqual((answer->Web.status, host.seen->Array.length), (503, 1))
  let empty = Web.request(
    "https://gateway.example.com/v1/01000004/",
    {method: "POST", headers: dict{}},
  )
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
  ignore(await state.drawApp(~random=() => 16777220.))
  await state.deploy({app: 16777220., binding, release: "", capacity: 1., kind: None})
  let answer = await Gateway.passed(
    reads(state),
    host.reach,
    ~port=36879,
    Web.request("https://gateway.example.com/v1/01000004/", {method: "GET", headers: dict{}}),
    {app: 16777220., path: "/"},
    ~search="",
  )
  let reason =
    JSON.parseOrThrow(await answer->Web.text)
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("reason"))
    ->Option.flatMap(JSON.Decode.string)
  deepEqual((answer->Web.status, reason, host.seen), (400, Some("beyond_host"), []))
})

test("an exact host wins over its parent wildcard and at most two keys are read", async () => {
  let keys = []
  let held = dict{"api.example.org": 1., "*.example.org": 2.}
  let state: State.reads = {
    domain: async name => {
      keys->Array.push(name)
      held->Dict.get(name)
    },
    deployment: async _ => None,
    binding: async _ => None,
    mount: async (~organization as _, ~scope as _) => None,
  }
  deepEqual(await Gateway.named(state, "API.EXAMPLE.ORG:443"), Some(1.))
  deepEqual(keys, ["api.example.org"])
  deepEqual(await Gateway.named(state, "blog.example.org"), Some(2.))
  deepEqual(keys, ["api.example.org", "blog.example.org", "*.example.org"])
  deepEqual(await Gateway.named(state, "a.b.example.org"), None)
  deepEqual(keys->Array.slice(~start=3), ["a.b.example.org", "*.b.example.org"])
})

test("the domain lookup uses the primary key even among unrelated domains", async () => {
  let plans = []
  let database = Sqlite.database(~plans, ())
  let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
  await run("INSERT INTO organization (id, label) VALUES (1, 'first')")
  await run("INSERT INTO binding (id, organization, secret) VALUES (2, 1, '')")
  await run("INSERT INTO release (hash, form, size) VALUES ('aa', 'modules', 3)")
  await run("INSERT INTO deployment (app, binding, release, capacity) VALUES (3, 2, 'aa', 1)")
  await run(
    "WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n WHERE v < 384) INSERT INTO domain (domain, app) SELECT 'host-' || v || '.example.org', 3 FROM n",
  )
  let reads = State.readsOfDatabase(database)
  deepEqual(await reads.domain("host-1.example.org"), Some(3.))
  deepEqual(await reads.domain("missing.example.net"), None)
  let domainPlans = plans->Array.filter(p => p.sql == "SELECT app FROM domain WHERE domain = ?")
  deepEqual(domainPlans->Array.length, 2)
  ok(
    domainPlans->Array.every(p =>
      p.rows->Array.some(r => r.detail->String.includes("SEARCH domain USING INDEX"))
    ),
  )
})

test("the mount lookup uses the primary key even among unrelated scopes", async () => {
  let plans = []
  let database = Sqlite.database(~plans, ())
  let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
  await run("INSERT INTO organization (id, label) VALUES (1, 'first')")
  await run("INSERT INTO binding (id, organization, secret) VALUES (2, 1, '')")
  await run("INSERT INTO release (hash, form, size) VALUES ('aa', 'modules', 3)")
  await run("INSERT INTO deployment (app, binding, release, capacity) VALUES (3, 2, 'aa', 1)")
  await run(
    "WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n WHERE v < 384) INSERT INTO scope (organization, scope, app) SELECT 1, 'scope-' || v, 3 FROM n",
  )
  let reads = State.readsOfDatabase(database)
  deepEqual(await reads.mount(~organization=1., ~scope="scope-1"), Some(3.))
  deepEqual(await reads.mount(~organization=1., ~scope="missing"), None)
  let mountPlans =
    plans->Array.filter(p => p.sql == "SELECT app FROM scope WHERE organization = ? AND scope = ?")
  deepEqual(mountPlans->Array.length, 2)
  ok(
    mountPlans->Array.every(p =>
      p.rows->Array.some(r => r.detail->String.includes("SEARCH scope USING INDEX"))
    ),
  )
})
