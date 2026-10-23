/***
 * The API held to RFC rxmd9 with its parts in memory and a host faked, each operation answering
 * its own caller alone and passing on what the host's driver answered.
 */
open Node
module Contracts = Envelope.Contracts
module Calls = Serve.Calls

let untrusted = (): Capability.Signed.trust => {
  root: Uint8Array.fromLength(32),
  certificates: [],
  now: 0.,
}

type stood = {parts: Api.parts, host: Host.t, artifacts: dict<Uint8Array.t>}

let stand = (~tunnels=?) => {
  let host = Host.make()
  let (artifacts, held) = Memory.artifacts()
  {
    parts: {
      state: Memory.state(),
      artifacts,
      reach: host.reach,
      tunnels,
      driverPort: 37483,
      origin: "https://control.test",
      wait: async () => (),
    },
    host,
    artifacts: held,
  }
}

/** A call made as a caller, its answer read as JSON. */
let called = async (stood, caller, envelope) => {
  let named = key =>
    envelope
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get(key))
    ->Option.flatMap(JSON.Decode.string)
    ->Option.getOr("")
  let answer = await Calls.serve(
    Api.routes(stood.parts, caller),
    ~trust=untrusted,
    {
      method_: "POST",
      path: `/${named("interface")}/${named("operation")}`,
      contentType: Some("application/json"),
      accept: Some("application/json"),
      body: Web.utf8(JSON.stringify(envelope)),
    },
  )
  (answer.status, JSON.parseOrThrow(Web.fromUtf8(answer.body)))
}

let organizations = call => Contracts.Interface.Organizations.toJson({call, capabilities: []})
let bindings = call => Contracts.Interface.Bindings.toJson({call, capabilities: []})
let releases = call => Contracts.Interface.Releases.toJson({call, capabilities: []})

let member = (json, name) =>
  json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))->Option.getOr(JSON.Null)
let data = json => json->member("data")
let reason = json => json->member("reason")->JSON.Decode.string

let artifact = Web.utf8("a bundle")

/** An organization, a bound binding and a release, as the operator and the host make them. */
let opened = async stood => {
  let (_, org) = await called(stood, Operator, organizations(Open({label: "first"})))
  let organization = org->data->member("organization")->JSON.Decode.float->Option.getOr(0.)
  let (_, binding) = await called(stood, Operator, bindings(Open({organization: organization})))
  let id = binding->data->member("binding")->JSON.Decode.float->Option.getOr(0.)
  ignore(await called(stood, Host(id), bindings(Bind({}))))
  let (_, put) = await called(stood, Operator, releases(Put({form: Modules, artifact})))
  let hash = put->data->member("hash")->JSON.Decode.string->Option.getOr("")
  (id, hash)
}

test("an organization opened twice by its label is one organization", async () => {
  let stood = stand()
  let (status, first) = await called(stood, Operator, organizations(Open({label: "first"})))
  let (_, again) = await called(stood, Operator, organizations(Open({label: "first"})))
  deepEqual((status, first->data, again->data), (200, first->data, first->data))
  let (_, bad) = await called(stood, Operator, organizations(Open({label: "Not-A-Label"})))
  deepEqual(bad->reason, Some("invalid"))
})

test("every operation refuses a caller it is not for as denied", async () => {
  let stood = stand()
  let refusals = [
    await called(stood, Nobody, organizations(Open({label: "first"}))),
    await called(stood, Host(1.), organizations(Open({label: "first"}))),
    await called(stood, Host(1.), bindings(Open({organization: 1.}))),
    await called(stood, Operator, bindings(Bind({}))),
    await called(stood, Nobody, releases(Put({form: Modules, artifact}))),
    await called(stood, Host(1.), releases(Describe({app: 1.}))),
  ]
  deepEqual(
    refusals->Array.map(((status, answer)) => (status, answer->reason)),
    Array.make(~length=6, (403, Some("denied"))),
  )
  // A host whose binding the control holds nothing of is denied too, as 3d3nt has it.
  deepEqual(
    (await called(stood, Host(9.), bindings(Bind({}))))->Pair.second->reason,
    Some("denied"),
  )
})

test("a binding is opened for an organization that is open, its secret answered once", async () => {
  let stood = stand()
  let (_, none) = await called(stood, Operator, bindings(Open({organization: 7.})))
  deepEqual(none->reason, Some("not_found"))
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  let (status, opened) = await called(stood, Operator, bindings(Open({organization: 1.})))
  let secret = opened->data->member("secret")->JSON.Decode.string->Option.getOr("")
  deepEqual(
    (status, Envelope.Base64url.decode(secret)->Option.map(TypedArray.length)),
    (200, Some(32)),
  )
  deepEqual(
    (await stood.parts.state.binding(1.))->Option.map(b => Envelope.Base64url.encode(b.secret)),
    Some(secret),
  )
})

test("a host bound with no tunnel to make is answered its address alone, again alike", async () => {
  let stood = stand()
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  ignore(await called(stood, Operator, bindings(Open({organization: 1.}))))
  let (status, bound) = await called(stood, Host(1.), bindings(Bind({})))
  let (_, again) = await called(stood, Host(1.), bindings(Bind({})))
  deepEqual(
    (status, bound->data),
    (200, JSON.parseOrThrow(`{"binding": 1, "address": "10.200.0.1"}`)),
  )
  deepEqual(again->data, bound->data)
})

/** Tunnels faked, counting what each made. */
let tunnels = (~failing=false) => {
  let made = ref(0)
  let routes = []
  let faked: Tunnels.t = {
    make: async name => {
      made := made.contents + 1
      failing ? Error("the API could not be reached") : Ok(`tunnel-${name}`)
    },
    route: async (~tunnel, ~address) => {
      routes->Array.push((tunnel, address))
      Ok()
    },
    token: async tunnel => Ok(`token of ${tunnel}`),
  }
  (faked, made, routes)
}

test("a host bound is made one tunnel and one route, and answered the tunnel's token", async () => {
  let (faked, made, routes) = tunnels()
  let stood = stand(~tunnels=faked)
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  ignore(await called(stood, Operator, bindings(Open({organization: 1.}))))
  let (_, bound) = await called(stood, Host(1.), bindings(Bind({})))
  let (_, again) = await called(stood, Host(1.), bindings(Bind({})))
  let tunnel =
    bound->data->member("tunnel")->JSON.Decode.string->Option.flatMap(Envelope.Base64url.decode)
  deepEqual(tunnel->Option.map(Web.fromUtf8), Some("token of tunnel-binding-1"))
  deepEqual(
    (made.contents, routes, again->data),
    (1, [("tunnel-binding-1", "10.200.0.1")], bound->data),
  )
})

test("a tunnel the API does not make is unreachable, and no address is kept", async () => {
  let (faked, _, _) = tunnels(~failing=true)
  let stood = stand(~tunnels=faked)
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  ignore(await called(stood, Operator, bindings(Open({organization: 1.}))))
  let (status, refused) = await called(stood, Host(1.), bindings(Bind({})))
  deepEqual((status, refused->reason), (503, Some("unreachable")))
  deepEqual((await stood.parts.state.binding(1.))->Option.flatMap(b => b.address), None)
})

test("a release is kept by the SHA-256 of its artifact, and past its bound refused", async () => {
  let stood = stand()
  let (_, put) = await called(stood, Operator, releases(Put({form: Modules, artifact})))
  let hash = Envelope.Hex.encode(await Web.sha256(artifact))
  deepEqual(put->data, JSON.parseOrThrow(`{"hash": "${hash}", "size": 8}`))
  deepEqual(stood.artifacts->Dict.get(hash), Some(artifact))
  let large = Uint8Array.fromLength(Api.artifactBound->Float.toInt + 1)
  let (status, refused) = await called(
    stood,
    Operator,
    releases(Put({form: Modules, artifact: large})),
  )
  deepEqual((status, refused->reason), (400, Some("too_large")))
})

test(
  "a deploy writes what was declared, then sends the host's driver a container and the app",
  async () => {
    let stood = stand()
    stood.host.slow := true
    let (binding, hash) = await opened(stood)
    let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
    let (status, answer) = await called(
      stood,
      Operator,
      releases(Deploy({binding, app: 4., release})),
    )
    deepEqual(
      (status, answer->data->member("state")->member("name")),
      (200, JSON.String("running")),
    )
    deepEqual(
      await stood.parts.state.deployment(4.),
      Some({app: 4., binding, release: hash, capacity: 1.}),
    )
    deepEqual(
      stood.host.deployed.contents->Option.map(d => (d.artifact.address, d.into)),
      Some((`https://control.test/artifacts/${hash}`, Some(1.))),
    )
    let token =
      (await stood.parts.state.binding(binding))->Option.map(b =>
        `Bearer ${Access.tokenText(b.id, b.secret)}`
      )
    ok(
      stood.host.seen->Array.every(s => s.authorization == token),
      ~message="every call carries the token",
    )
    deepEqual(
      stood.host.seen->Array.map(s => Web.parts(s.url)->Web.pathname),
      [
        "/management/describe",
        "/management/apply",
        "/management/describe",
        "/management/describe",
        "/deployments/deploy",
      ],
    )
    let (_, described) = await called(stood, Operator, releases(Describe({app: 4.})))
    deepEqual(described->data, answer->data)
  },
)

test(
  "a deploy onto a binding not bound, or of a release not kept, is refused before any call",
  async () => {
    let stood = stand()
    ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
    ignore(await called(stood, Operator, bindings(Open({organization: 1.}))))
    let release = Uint8Array.fromLength(32)
    let (_, unbound) = await called(
      stood,
      Operator,
      releases(Deploy({binding: 1., app: 1., release})),
    )
    let (_, none) = await called(stood, Operator, releases(Deploy({binding: 2., app: 1., release})))
    ignore(await called(stood, Host(1.), bindings(Bind({}))))
    let (_, unkept) = await called(
      stood,
      Operator,
      releases(Deploy({binding: 1., app: 1., release})),
    )
    let (_, undeployed) = await called(stood, Operator, releases(Describe({app: 1.})))
    deepEqual(
      [unbound, none, unkept, undeployed]->Array.map(reason),
      [Some("unbound"), Some("not_found"), Some("not_found"), Some("not_found")],
    )
    deepEqual(stood.host.seen, [])
  },
)

test("a host that does not answer is unreachable, and the caller may try again", async () => {
  let stood = stand()
  let (binding, hash) = await opened(stood)
  stood.host.gone := true
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  let (status, refused) = await called(
    stood,
    Operator,
    releases(Deploy({binding, app: 1., release})),
  )
  deepEqual((status, refused->reason), (503, Some("unreachable")))
  stood.host.gone := false
  let (again, _) = await called(stood, Operator, releases(Deploy({binding, app: 1., release})))
  deepEqual(again, 200)
})

test("a binding's address is its id within 10.200.0.0/16", async () =>
  deepEqual(
    [1., 255., 256., 65535.]->Array.map(Api.addressOf),
    ["10.200.0.1", "10.200.0.255", "10.200.1.0", "10.200.255.255"],
  )
)
