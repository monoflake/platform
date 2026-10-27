open Node
module Stores = ControlOrganization.Stores
module State = ControlOrganization.State
module Reach = ControlOrganization.Reach

let request = (~method="GET", path, ~headers=dict{}, ~body=?) =>
  Web.request(`https://gateway.example.com${path}`, {method, headers, ?body})

let deployed = async (~secret=String.repeat("ab", 32), ()) => {
  let database = Sqlite.database()
  let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
  await run("INSERT INTO organization (id, label) VALUES (1, 'first')")
  await run(
    `INSERT INTO binding (id, organization, secret, address, bound)
    VALUES (2, 1, '${secret}', '10.200.0.2', 1)`,
  )
  await run("INSERT INTO release (hash, form, size) VALUES ('aa', 'modules', 3)")
  await run("INSERT INTO app (id) VALUES (16777220)")
  await run("INSERT INTO deployment (app, binding, release, capacity)
    VALUES (16777220, 2, 'aa', 1)")
  database
}

type secretRow = {secret: string}

test("the database view offers two reads, no writes and no secret fields", async () => {
  let database = await deployed()
  let seen = []
  let reads = State.readsOfDatabase(Reading.guarded(database, seen))
  deepEqual(Reading.offered(reads), ["binding", "deployment"])
  let binding = (await reads.binding(2.))->Option.getOrThrow
  deepEqual(Reading.offered(binding), ["address", "bound", "origin"])
  deepEqual(binding, {address: Some("10.200.0.2"), origin: None, bound: Some(1.)})
  deepEqual((await reads.deployment(16777220.))->Option.map(d => d.binding), Some(2.))
  deepEqual((await reads.binding(99.), await reads.deployment(99.)), (None, None))
  deepEqual(
    seen,
    [
      "SELECT id, organization, secret, tunnel, address, origin, relayed, bound FROM binding WHERE id = ?",
      "SELECT app, binding, release, capacity, kind FROM deployment WHERE app = ?",
      "SELECT id, organization, secret, tunnel, address, origin, relayed, bound FROM binding WHERE id = ?",
      "SELECT app, binding, release, capacity, kind FROM deployment WHERE app = ?",
    ],
  )
  let kept: Nullable.t<secretRow> = await database
  ->Stores.prepare("SELECT secret FROM binding WHERE id = 2")
  ->Stores.bind([])
  ->Stores.first
  deepEqual(kept->Nullable.toOption->Option.map(row => row.secret), Some(String.repeat("ab", 32)))
})

test(
  "the bundled Worker exports fetch and passes a mount with its request and response intact",
  async () => {
    let worker = await Workerd.bundled()
    deepEqual((await worker.fetch(request("/"), {}))->Web.status, 404)
    let database = await deployed()
    let seen = []
    let sent = []
    let reach = async request => {
      let header = name => request->Web.requestHeaders->Web.header(name)->Nullable.toOption
      let body = Web.fromUtf8(await request->Web.bytesOf)
      sent->Array.push((
        request->Web.url,
        request->Web.method_,
        header("host"),
        header("x-forwarded-host"),
        header("x-client"),
        body,
      ))
      Web.response(
        Web.utf8("from app"),
        {
          status: 201,
          headers: dict{
            "content-type": "application/json",
            "x-app": "answer",
            "set-cookie": "kept=1",
          },
        },
      )
    }
    let env: Stores.env = {
      state: Reading.guarded(database, seen),
      hosts: Reading.fetcher(reach),
      entryPort: "43210",
    }
    let answer = await worker.fetch(
      request(
        ~method="POST",
        "/v7/01000004/hello?x=1",
        ~headers=dict{"x-client": "caller"},
        ~body=Web.utf8("body"),
      ),
      env,
    )
    deepEqual((answer->Web.status, await answer->Web.text), (201, "from app"))
    deepEqual(
      sent,
      [
        (
          "http://10.200.0.2:43210/hello?x=1",
          "POST",
          Some("01000004.b00000002"),
          Some("01000004.b00000002"),
          Some("caller"),
          "body",
        ),
      ],
    )
    deepEqual(
      ["content-type", "x-app", "set-cookie"]->Array.map(name =>
        answer->Web.responseHeaders->Web.header(name)->Nullable.toOption
      ),
      [Some("application/json"), Some("answer"), Some("kept=1")],
    )
    deepEqual(seen->Array.length, 2)
  },
)

test("the gateway defaults to the shared entry port", async () => {
  let database = await deployed()
  let sent = []
  let env: Stores.env = {
    state: database,
    hosts: Reading.fetcher(async request => {
      sent->Array.push(request->Web.url)
      Web.answered(~status=200, "app")
    }),
  }
  deepEqual((await Worker.default.fetch(request("/v1/01000004/"), env))->Web.status, 200)
  deepEqual(sent, [`http://10.200.0.2:${Int.toString(Reach.entryPort)}/`])
})

test("a mount never opens or reseals a binding secret", async () => {
  let secrets = [String.repeat("ab", 32), "01unreadable", ""]
  for i in 0 to secrets->Array.length - 1 {
    let database = await deployed(~secret=secrets->Array.getUnsafe(i), ())
    let seen = []
    let env: Stores.env = {
      state: Reading.guarded(database, seen),
      hosts: Reading.fetcher(async _ => Web.answered(~status=200, "app")),
    }
    deepEqual((await Worker.default.fetch(request("/v1/01000004/"), env))->Web.status, 200)
    deepEqual(seen->Array.length, 2)
  }
})

test("the gateway answers no control route, root or direct domain path", async () => {
  let paths = [
    "/",
    "/organizations/open",
    "/artifacts/" ++ String.repeat("ab", 32),
    "/relay/10.200.0.1/36879/",
    "/object/read",
    "/hello",
    "/v1/00000000/",
    "/v1/01000004x/",
  ]
  for i in 0 to paths->Array.length - 1 {
    for j in 0 to 1 {
      deepEqual(
        (
          await Worker.default.fetch(
            request(~method=j == 0 ? "GET" : "POST", paths->Array.getUnsafe(i)),
            {},
          )
        )->Web.status,
        404,
      )
    }
  }
  deepEqual((await Worker.default.fetch(request("/v1/01000004/"), {}))->Web.status, 500)
})

test("both Workers choose the same network, local and relayed reach", async () => {
  let environments: array<Stores.env> = [
    {hosts: Reading.fetcher(async _ => Web.answered(~status=200, "network"))},
    {reach: "localhost"},
    {standsOn: "https://control.example.com", standsOnToken: "token"},
    {standsOn: "https://control.example.com", standsOnToken: "token", reach: "localhost"},
    {},
  ]
  let origins = environments->Array.map(env => {
    let at = reach =>
      reach->Option.map(
        (r: ControlOrganization.Reach.t) => r.origin(~address="10.200.0.2", ~port=36879),
      )
    let gateway = at(Worker.reachOf(env))
    deepEqual(gateway, at(ControlOrganization.Worker.reachOf(env)))
    gateway
  })
  deepEqual(
    origins,
    [
      Some("http://10.200.0.2:36879"),
      Some("http://localhost:36879"),
      Some("https://control.example.com/relay/10.200.0.2/36879"),
      Some("http://localhost:36879"),
      None,
    ],
  )
})

test(
  "the gateway configuration shares the control database and placement without a route",
  async () => {
    let config = path =>
      JSON.parseOrThrow(readText(fromRoot(path)))->JSON.Decode.object->Option.getOrThrow
    let control = config("code/products/control/wrangler.json")
    let gateway = config("code/products/gateway/wrangler.json")
    for i in 0 to 1 {
      let key = i == 0 ? "placement" : "compatibility_date"
      deepEqual(gateway->Dict.get(key), control->Dict.get(key))
    }
    let database = c =>
      c
      ->Dict.getUnsafe("d1_databases")
      ->JSON.Decode.array
      ->Option.getOrThrow
      ->Array.getUnsafe(0)
      ->JSON.Decode.object
      ->Option.getOrThrow
    let same =
      ["binding", "database_name", "database_id"]->Array.map(key => (
        database(gateway)->Dict.get(key),
        database(control)->Dict.get(key),
      ))
    same->Array.forEach(((a, b)) => deepEqual(a, b))
    deepEqual(gateway->Dict.get("workers_dev"), Some(JSON.Boolean(false)))
    deepEqual(gateway->Dict.get("preview_urls"), Some(JSON.Boolean(false)))
    deepEqual((gateway->Dict.get("routes"), gateway->Dict.get("route")), (None, None))
  },
)
