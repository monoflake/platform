/*** `Relay` held to RFC rxmd9, an organization's own control given its own hosts and objects. */
open Node

let secret = Uint8Array.fromLength(32)

/** Two organizations, the first's storage binding bound here and its relayed binding opened. */
let stood = async () => {
  let state = Memory.state()
  let {id: first} = await state.openOrganization("first", ~secret)
  let {id: second} = await state.openOrganization("second", ~secret)
  let storage = await state.openBinding(~organization=first, ~secret, ~relayed=false)
  await state.addressed(~binding=storage, ~address="10.200.0.1")
  let relayed = await state.openBinding(~organization=first, ~secret, ~relayed=true)
  await state.addressed(~binding=relayed, ~address="10.200.0.2")
  (state, first, second, relayed)
}

let request = (url, headers) => Web.request(url, {method: "POST", headers, body: Web.utf8("{}")})

test("a relayed path names its binding, its listener and what the host is handed", async () =>
  deepEqual(
    [
      "/relay/2/driver/deployments/deploy",
      "/relay/2/entry",
      "/relay/0/entry/",
      "/relay/2/console/",
      "/organizations/open",
    ]->Array.map(Relay.routed),
    [
      Some({binding: 2., listener: Driver, path: "/deployments/deploy"}),
      Some({binding: 2., listener: Entry, path: "/"}),
      None,
      None,
      None,
    ],
  )
)

test(
  "a relay reaches the organization's own relayed host alone, its proxy's credential dropped",
  async () => {
    let (state, first, second, relayed) = await stood()
    let host = Host.make()
    let passed = (caller, binding, listener) =>
      Relay.passed(
        state,
        host.reach,
        ~caller,
        ~ports=(37483, 36879),
        request(
          "https://control.test/relay",
          dict{"authorization": "Bearer the host's", "proxy-authorization": "Bearer the org's"},
        ),
        {binding, listener, path: "/deployments/describe"},
        ~search="",
      )
    let statuses = [
      (await passed(Organization(first), relayed, Driver))->Web.status,
      (await passed(Organization(second), relayed, Driver))->Web.status,
      (await passed(Organization(first), 1., Driver))->Web.status,
      (await passed(Operator, relayed, Driver))->Web.status,
    ]
    deepEqual(statuses, [404, 404, 404, 403])
    deepEqual(
      host.seen->Array.map(s => (s.url, s.authorization)),
      [("http://10.200.0.2:37483/deployments/describe", Some("Bearer the host's"))],
    )
    ignore(await passed(Organization(first), relayed, Entry))
    deepEqual(
      host.seen->Array.at(-1)->Option.map(s => s.url),
      Some("http://10.200.0.2:36879/deployments/describe"),
    )
  },
)

test("an object call reaches the storage binding's driver by that binding's token", async () => {
  let (state, first, second, _) = await stood()
  let host = Host.make()
  let stored = caller =>
    Relay.stored(
      state,
      host.reach,
      ~caller,
      ~port=37483,
      request("https://control.test/object/write", dict{"authorization": "Bearer the org's"}),
      ~path="/object/write",
    )
  ignore(await stored(Organization(first)))
  deepEqual(
    host.seen->Array.map(s => (s.url, s.authorization)),
    [("http://10.200.0.1:37483/object/write", Some(`Bearer ${Access.tokenText(1., secret)}`))],
  )
  deepEqual(
    [(await stored(Organization(second)))->Web.status, (await stored(Host(1.)))->Web.status],
    [409, 403],
  )
  deepEqual([Relay.objected("/object/write"), Relay.objected("/object/")], [true, false])
})
