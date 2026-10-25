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

test("a relayed path names an address, a port and what the host is handed", async () =>
  deepEqual(
    [
      "/relay/10.200.0.2/37483/deployments/deploy",
      "/relay/10.200.0.2/36879",
      "/relay/10.200.0.2/0/",
      "/relay/192.168.0.2/36879/",
      "/organizations/open",
    ]->Array.map(Relay.routed),
    [
      Some({address: "10.200.0.2", port: 37483, path: "/deployments/deploy"}),
      Some({address: "10.200.0.2", port: 36879, path: "/"}),
      None,
      None,
      None,
    ],
  )
)

test(
  "a relay reaches the organization's own relayed host alone, its proxy's credential dropped",
  async () => {
    let (state, first, second, _) = await stood()
    let host = Host.make()
    let passed = (caller, address, port) =>
      Relay.passed(
        state,
        host.reach,
        ~caller,
        ~ports=[37483, 36879],
        request(
          "https://control.test/relay",
          dict{"authorization": "Bearer the host's", "proxy-authorization": "Bearer the org's"},
        ),
        {address, port, path: "/hello"},
        ~search="",
      )
    let statuses = [
      (await passed(Organization(first), "10.200.0.2", 37483))->Web.status,
      (await passed(Organization(second), "10.200.0.2", 37483))->Web.status,
      (await passed(Organization(first), "10.200.0.1", 37483))->Web.status,
      (await passed(Organization(first), "10.200.0.2", 22))->Web.status,
      (await passed(Operator, "10.200.0.2", 37483))->Web.status,
    ]
    deepEqual(statuses, [200, 404, 404, 404, 403])
    deepEqual(
      host.seen->Array.map(s => (s.url, s.authorization)),
      [("http://10.200.0.2:37483/hello", Some("Bearer the host's"))],
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
      ~wait=async () => (),
      request("https://control.test/object/write", dict{"authorization": "Bearer the org's"}),
      ~path="/object/write",
    )
  ignore(await stored(Organization(first)))
  deepEqual(
    host.seen->Array.slice(~start=0, ~end=1)->Array.map(s => (s.url, s.authorization)),
    [("http://10.200.0.1:37483/object/write", Some(`Bearer ${Access.tokenText(1., secret)}`))],
  )
  deepEqual(
    [(await stored(Organization(second)))->Web.status, (await stored(Host(1.)))->Web.status],
    [409, 403],
  )
  deepEqual([Relay.objected("/object/write"), Relay.objected("/object/")], [true, false])
})

test(
  "a write the storage binding has no bucket for makes it one, and is sent once more",
  async () => {
    let (state, first, _, _) = await stood()
    let host = Host.make()
    let answer = await Relay.stored(
      state,
      host.reach,
      ~caller=Organization(first),
      ~port=37483,
      ~wait=async () => (),
      request("https://control.test/object/write", dict{"authorization": "Bearer the org's"}),
      ~path="/object/write",
    )
    deepEqual(answer->Web.status, 200)
    deepEqual(
      host.seen->Array.map(s => Web.parts(s.url)->Web.pathname),
      [
        "/object/write",
        "/management/describe",
        "/management/apply",
        "/management/describe",
        "/object/write",
      ],
    )
  },
)

/** An answer's status and its reason, as a client of the relay reads an error. */
let reasoned = async answer => (
  answer->Web.status,
  JSON.parseOrThrow(await answer->Web.text)
  ->JSON.Decode.object
  ->Option.flatMap(o => o->Dict.get("reason"))
  ->Option.flatMap(JSON.Decode.string),
)

test(
  "a binding reached by its origin is beyond the relay's host, its driver never called",
  async () => {
    let state = Memory.state()
    let {id: organization} = await state.openOrganization("first", ~secret)
    let binding = await state.openBinding(~organization, ~secret, ~relayed=true)
    ignore(await state.originated(~binding, ~origin="https://driver.example.com"))
    // Storage chooses no origin binding, so a state that did is stood in for here.
    let origined =
      (await state.binding(binding))->Option.map(b => {...b, address: Some("10.200.0.2")})
    let state = {...state, storage: async _ => origined, addressedAt: async _ => origined}
    let host = Host.make()
    let stored = await Relay.stored(
      state,
      host.reach,
      ~caller=Organization(organization),
      ~port=37483,
      ~wait=async () => (),
      request("https://control.test/object/write", dict{}),
      ~path="/object/write",
    )
    let passed = await Relay.passed(
      state,
      host.reach,
      ~caller=Organization(organization),
      ~ports=[37483],
      request("https://control.test/relay", dict{}),
      {address: "10.200.0.2", port: 37483, path: "/"},
      ~search="",
    )
    deepEqual(
      [await reasoned(stored), await reasoned(passed)],
      [(400, Some("beyond_host")), (400, Some("beyond_host"))],
    )
    deepEqual(host.seen, [])
  },
)
