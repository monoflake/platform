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
  await run("INSERT INTO scope (organization, scope, app) VALUES (1, 'hello', 16777220)")
  database
}

/** The first organization's id as the gateway's configuration writes it. */
let organization = "00000001"

type secretRow = {secret: string}

test("the database view offers only routing reads, no writes and no secret fields", async () => {
  let database = await deployed()
  let seen = []
  let reads = State.readsOfDatabase(Reading.guarded(database, seen))
  deepEqual(Reading.offered(reads), ["binding", "deployment", "domain", "mount"])
  let binding = (await reads.binding(2.))->Option.getOrThrow
  deepEqual(Reading.offered(binding), ["address", "bound", "origin"])
  deepEqual(binding, {address: Some("10.200.0.2"), origin: None, bound: Some(1.)})
  deepEqual((await reads.deployment(16777220.))->Option.map(d => d.binding), Some(2.))
  deepEqual((await reads.binding(99.), await reads.deployment(99.)), (None, None))
  deepEqual(
    seen,
    [
      "SELECT id, organization, secret, tunnel, address, origin, relayed, bound FROM binding WHERE id = ?",
      "SELECT app, binding, release, capacity, kind, ingress FROM deployment WHERE app = ?",
      "SELECT id, organization, secret, tunnel, address, origin, relayed, bound FROM binding WHERE id = ?",
      "SELECT app, binding, release, capacity, kind, ingress FROM deployment WHERE app = ?",
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
    deepEqual((await worker.fetch(request("/"), {}))->Web.status, 500)
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
      organization,
    }
    let answer = await worker.fetch(
      request(
        ~method="POST",
        "/v7/hello/hello?x=1",
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
    deepEqual(seen->Array.length, 5)
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
    organization,
  }
  deepEqual((await Worker.default.fetch(request("/v1/hello/"), env))->Web.status, 200)
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
      organization,
    }
    deepEqual((await Worker.default.fetch(request("/v1/hello/"), env))->Web.status, 200)
    deepEqual(seen->Array.length, 5)
  }
})

test("the gateway answers no control route, root, app id or undeclared scope", async () => {
  let env: Stores.env = {
    state: await deployed(),
    hosts: Reading.fetcher(async _ => Web.answered(~status=200, "app")),
    organization,
  }
  let paths = [
    "/",
    "/organizations/open",
    "/artifacts/" ++ String.repeat("ab", 32),
    "/relay/10.200.0.1/36879/",
    "/object/read",
    "/hello",
    "/v1/00000000/",
    "/v1/01000004/",
    "/v1/01000004x/",
    "/v1/app-16777220/",
    "/v1/other/",
  ]
  for i in 0 to paths->Array.length - 1 {
    for j in 0 to 1 {
      deepEqual(
        (
          await Worker.default.fetch(
            request(~method=j == 0 ? "GET" : "POST", paths->Array.getUnsafe(i)),
            env,
          )
        )->Web.status,
        404,
      )
    }
  }
  deepEqual((await Worker.default.fetch(request("/v1/hello/"), {}))->Web.status, 500)
})

test("one gateway name reads one organization's mounts, refused where none is named", async () => {
  let database = await deployed()
  let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
  await run("INSERT INTO domain (domain, app) VALUES ('example.com', 16777220)")
  let env: Stores.env = {
    state: database,
    hosts: Reading.fetcher(async _ => Web.answered(~status=200, "app")),
  }
  let asked = async (~organization=?, ~host="gateway.example.com", path) =>
    (
      await Worker.default.fetch(
        request(path, ~headers=dict{"host": host}),
        {...env, ?organization},
      )
    )->Web.status
  deepEqual(await asked(~organization="00000001", "/v1/hello/"), 200)
  deepEqual(await asked(~organization="00000002", "/v1/hello/"), 404)
  let unnamed = ["", "1", "app-1", "00000000", "0000000G"]
  for i in 0 to unnamed->Array.length - 1 {
    let organization = unnamed->Array.getUnsafe(i)
    deepEqual(await asked(~organization, "/v1/hello/"), 500, ~message=organization)
  }
  deepEqual(await asked("/v1/hello/"), 500)
  // A direct domain names its app itself, with no organization to read.
  deepEqual(await asked(~host="example.com", "/"), 200)
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
    // Refused until a deployment fills it, so a gateway serves no organization by default.
    deepEqual(
      gateway
      ->Dict.get("vars")
      ->Option.flatMap(JSON.Decode.object)
      ->Option.flatMap(vars => vars->Dict.get("ORGANIZATION")),
      Some(JSON.String("")),
    )
  },
)

test(
  "declared exact and wildcard hosts carry the whole path and query to the binding",
  async () => {
    let database = await deployed()
    let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
    await run("INSERT INTO app (id) VALUES (16777221)")
    await run(
      "INSERT INTO deployment (app, binding, release, capacity) VALUES (16777221, 2, 'aa', 1)",
    )
    await run(
      "INSERT INTO domain (domain, app) VALUES ('example.com', 16777220), ('*.example.org', 16777220), ('api.example.org', 16777221)",
    )
    let seen = []
    let sent = []
    let env: Stores.env = {
      state: Reading.guarded(database, seen),
      hosts: Reading.fetcher(async request => {
        sent->Array.push((
          request->Web.url,
          request->Web.method_,
          request->Web.requestHeaders->Web.header("host")->Nullable.toOption,
          request->Web.requestHeaders->Web.header("x-forwarded-host")->Nullable.toOption,
          Web.fromUtf8(await request->Web.bytesOf),
        ))
        Web.answered(~status=201, "app")
      }),
      entryPort: "43210",
      organization,
    }
    let path = "/v7/01000004/a%2Fb//c?x=%2f&x=+&empty="
    let hosts = ["EXAMPLE.COM:443", "blog.example.org", "API.EXAMPLE.ORG:8443"]
    for i in 0 to hosts->Array.length - 1 {
      deepEqual(
        (
          await Worker.default.fetch(
            request(
              ~method="POST",
              path,
              ~headers=dict{"host": hosts->Array.getUnsafe(i)},
              ~body=Web.utf8("body"),
            ),
            env,
          )
        )->Web.status,
        201,
      )
    }
    let expected = app => (`http://10.200.0.2:43210${path}`, "POST", Some(app), Some(app), "body")
    deepEqual(
      sent,
      [
        expected("01000004.b00000002"),
        expected("01000004.b00000002"),
        expected("01000005.b00000002"),
      ],
    )
    deepEqual(seen->Array.length, 10)
    let fallback = await Worker.default.fetch(
      request("/v1/hello/hello?x=1", ~headers=dict{"host": "unmatched.example.net"}),
      env,
    )
    deepEqual(fallback->Web.status, 201)
    deepEqual(
      sent->Array.at(-1)->Option.map(((url, _, _, _, _)) => url),
      Some("http://10.200.0.2:43210/hello?x=1"),
    )
    deepEqual(
      (
        await Worker.default.fetch(
          request("/hello", ~headers=dict{"host": "unmatched.example.net"}),
          env,
        )
      )->Web.status,
      404,
    )
    deepEqual(
      (
        await Worker.default.fetch(request("/hello", ~headers=dict{"host": "a.b.example.org"}), env)
      )->Web.status,
      404,
    )
  },
)

test("a direct domain is read from the URL when no Host header is present", async () => {
  let database = await deployed()
  await database
  ->Stores.prepare("INSERT INTO domain (domain, app) VALUES ('gateway.example.com', 16777220)")
  ->Stores.bind([])
  ->Stores.run
  let env: Stores.env = {
    state: database,
    hosts: Reading.fetcher(async _ => Web.answered(~status=200, "app")),
  }
  deepEqual((await Worker.default.fetch(request("/"), env))->Web.status, 200)
})

test("the reserved scope reaches the configured storage with its whole path, guarded", async () => {
  let database = await deployed()
  let sent = []
  let reach = async request => {
    sent->Array.push((
      request->Web.url,
      request->Web.requestHeaders->Web.header("host")->Nullable.toOption,
    ))
    Web.response(Web.utf8("hello"), {status: 200, headers: dict{"content-type": "text/plain"}})
  }
  let env: Stores.env = {
    state: Reading.guarded(database, []),
    hosts: Reading.fetcher(reach),
    entryPort: "43210",
    organization,
  }
  env->Configured.setStorage("0a0b0c0d.b00000002")
  let object = `/v1/storage/00000001/${String.repeat("ab", 32)}.txt`
  let answer = await Worker.default.fetch(request(object), env)
  deepEqual((answer->Web.status, await answer->Web.text), (200, "hello"))
  deepEqual(sent, [(`http://10.200.0.2:43210${object}`, Some("0a0b0c0d.b00000002"))])
  deepEqual(
    ["x-content-type-options", "content-security-policy"]->Array.map(name =>
      answer->Web.responseHeaders->Web.header(name)->Nullable.toOption
    ),
    [Some("nosniff"), Some("sandbox")],
  )
})

test("every answer is guarded, a PDF opened unsandboxed alone", async () => {
  let pdf = Gateway.guarded(
    Web.response(Web.utf8("%PDF"), {status: 200, headers: dict{"content-type": "application/pdf"}}),
  )
  deepEqual(
    (
      pdf->Web.responseHeaders->Web.header("x-content-type-options")->Nullable.toOption,
      pdf->Web.responseHeaders->Web.header("content-security-policy")->Nullable.toOption,
    ),
    (Some("nosniff"), None),
  )
  let missing = await Worker.default.fetch(request("/nothing"), {})
  deepEqual(
    missing->Web.responseHeaders->Web.header("content-security-policy")->Nullable.toOption,
    Some("sandbox"),
  )
})

test("a scope other than storage, or no configured storage, routes as a mount", async () => {
  let object = `/v1/storage/00000001/${String.repeat("ab", 32)}.txt`
  deepEqual(Gateway.stored(~configured="0a0b0c0d.b00000002", object), Some((168496141., 2.)))
  deepEqual(Gateway.stored(~configured="0a0b0c0d.b00000002", "/v1/hello/x"), None)
  deepEqual(Gateway.stored(~configured="not a host", object), None)
})
