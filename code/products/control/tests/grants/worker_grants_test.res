open Node
open Grant_fixture

test(
  "Worker routes authenticate a synthetic health grant and disable caching with no driver access",
  async () => {
    let t = await make()
    t.time := Date.now()
    let grant = await mint(t, ~health=true, ~expires=t.time.contents +. 60000., ())
    let nonce = Uint8Array.fromLength(32)
    let env: Stores.env = {
      state: t.context.store.database,
      artifacts: Routes.bucket(),
      hosts: Routes.fetcher(async _ => {
        ok(false)
        JsError.throwWithMessage("no driver")
      }),
    }
    let request = (~body=JSON.stringify(envelope(Health({nonce: nonce}))), ()) =>
      Web.request(
        "https://control.test/deployment_grants/health",
        {
          method: "POST",
          headers: dict{
            "authorization": `Bearer ${grant.bearer}`,
            "content-type": "application/json",
            "accept": "application/json",
          },
          body: Web.utf8(body),
        },
      )
    let response = await Worker.default.fetch(request(), env)
    deepEqual(response->Web.status, 200)
    deepEqual(
      response->Web.responseHeaders->Web.header("cache-control")->Nullable.toOption,
      Some("no-store"),
    )
    let json = JSON.parseOrThrow(await Web.text(response))
    deepEqual(json->Called.data, C.HealthAnswer.toJson({nonce, state: Ready}))
    let unavailable = await Worker.default.fetch(request(), {...env, artifacts: ?None})
    deepEqual(unavailable->Web.status, 200)
    deepEqual(
      JSON.parseOrThrow(await Web.text(unavailable))->Called.data,
      C.HealthAnswer.toJson({nonce, state: Unavailable}),
    )
    let oversized = await Worker.default.fetch(request(~body=String.repeat("x", 8193), ()), env)
    deepEqual(oversized->Web.status, 413)
  },
)

test(
  "grant requests decode before looking up credentials and never expose store exceptions",
  async () => {
    let t = await make()
    t.time := Date.now()
    let grant = await mint(t, ~health=true, ~expires=t.time.contents +. 60000., ())
    let env: Stores.env = {
      state: Sqlite.refusing(t.context.store.database, "SELECT grant"),
      artifacts: Routes.bucket(),
      reach: "localhost",
    }
    let request = body =>
      Web.request(
        "https://control.test/deployment_grants/health",
        {
          method: "POST",
          headers: dict{
            "authorization": `Bearer ${grant.bearer}`,
            "content-type": "application/json",
            "accept": "application/json",
          },
          body: Web.utf8(body),
        },
      )
    let malformed = await Worker.default.fetch(request("{}"), env)
    deepEqual(malformed->Web.status, 400)
    let unavailable = await Worker.default.fetch(
      request(JSON.stringify(envelope(Health({nonce: Uint8Array.fromLength(32)})))),
      env,
    )
    ok(unavailable->Web.status >= 400)
    deepEqual((await Web.text(unavailable))->String.includes("SELECT"), false)
  },
)
