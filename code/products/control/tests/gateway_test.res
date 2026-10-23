/*** `Gateway` held to RFCs vr5lw and rxmd9, an app's scope read and dropped, its host named. */
open Node

test("a path under an app's scope hands the app what follows it, its root at least", async () =>
  deepEqual(
    [
      "/v1/app-1",
      "/v1/app-1/",
      "/v2/app-42/a/b",
      "/v1/app-0/",
      "/v1/app-1x/",
      "/app-1/",
      "/v1/",
      "/organizations/open",
    ]->Array.map(Gateway.routed),
    [
      Some({app: 1., path: "/"}),
      Some({app: 1., path: "/"}),
      Some({app: 42., path: "/a/b"}),
      None,
      None,
      None,
      None,
      None,
    ],
  )
)

test("the entry is asked by the host deploy names, app then binding", async () =>
  deepEqual(Gateway.host(~app=1., ~binding=3.), "app-1.b3")
)

test(
  "a request passed reaches the binding's entry by its host, and an app not deployed is not",
  async () => {
    let state = Memory.state()
    let host = Host.make()
    let request = Web.request(
      "https://control.test/v1/app-4/hello?x=1",
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
    let organization = await state.openOrganization("first")
    let binding = await state.openBinding(~organization, ~secret=Uint8Array.fromLength(32))
    await state.addressed(~binding, ~address="10.200.0.1")
    await state.deploy({app: 4., binding, release: "", capacity: 1.})
    let answer = await Gateway.passed(
      state,
      host.reach,
      ~port=36879,
      request,
      {app: 4., path: "/hello"},
      ~search="?x=1",
    )
    deepEqual(await answer->Web.text, "entry asked /hello for app-4.b1")
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
