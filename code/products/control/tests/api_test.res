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

/** A fetch for origins that no test reaches. */
let nowhere: Web.fetch = async _ => JsError.throwWithMessage("no origin is reached here")

let stand = (~tunnels=?, ~standing=?, ~direct=nowhere) => {
  let host = Host.make()
  let (artifacts, held) = Memory.artifacts()
  {
    parts: {
      state: Memory.state(),
      artifacts,
      reach: host.reach,
      tunnels,
      standing,
      driverPort: 37483,
      direct,
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
let reaches = call => Contracts.Interface.Reaches.toJson({call, capabilities: []})

let member = (json, name) =>
  json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))->Option.getOr(JSON.Null)
let data = json => json->member("data")
let reason = json => json->member("reason")->JSON.Decode.string

let artifact = Web.utf8("a bundle")

/** The binding opened for an organization, its id as the control drew it. */
let openBinding = async (stood, organization) => {
  let (_, opened) = await called(stood, Operator, bindings(Open({organization: organization})))
  opened->data->member("binding")->JSON.Decode.float->Option.getOr(0.)
}

/** An organization, a bound binding and a release, as the operator and the host make them. */
let opened = async stood => {
  let (_, org) = await called(stood, Operator, organizations(Open({label: "first"})))
  let organization = org->data->member("organization")->JSON.Decode.float->Option.getOr(0.)
  let (_, binding) = await called(stood, Operator, bindings(Open({organization: organization})))
  let id = binding->data->member("binding")->JSON.Decode.float->Option.getOr(0.)
  ignore(await called(stood, Host(id), bindings(Bind({reach: Tunnel}))))
  let (_, put) = await called(stood, Operator, releases(Put({form: Modules, artifact})))
  let hash = put->data->member("hash")->JSON.Decode.string->Option.getOr("")
  (id, hash)
}

/** The app a deploy answered it runs. */
let ranAs = answer => answer->data->member("runs")->member("id")->JSON.Decode.float

/** The app a refusal names as drawn for the deploy it refused, `app <8 hex>, ` first. */
let named = answer =>
  switch answer->member("message")->JSON.Decode.string {
  | Some(message) if /^app [0-9a-f]{8}, /->RegExp.test(message) =>
    Ids.ofText(message->String.slice(~start=4, ~end=12))
  | Some(_) | None => None
  }

test("an organization opened twice by its label is one organization", async () => {
  let stood = stand()
  let (status, first) = await called(stood, Operator, organizations(Open({label: "first"})))
  let (_, again) = await called(stood, Operator, organizations(Open({label: "first"})))
  deepEqual((status, first->data, again->data), (200, first->data, first->data))
  let (_, bad) = await called(stood, Operator, organizations(Open({label: "Not-A-Label"})))
  deepEqual(bad->reason, Some("invalid"))
})

test("an organization is answered its secret, the same each time it is opened", async () => {
  let stood = stand()
  let (_, first) = await called(stood, Operator, organizations(Open({label: "first"})))
  let (_, again) = await called(stood, Operator, organizations(Open({label: "first"})))
  let secret = first->data->member("secret")->JSON.Decode.string
  deepEqual(
    secret->Option.flatMap(Envelope.Base64url.decode)->Option.map(TypedArray.length),
    Some(32),
  )
  deepEqual(again->data->member("secret")->JSON.Decode.string, secret)
  deepEqual(
    (await stood.parts.state.organizationSecret(1.))->Option.map(Envelope.Base64url.encode),
    secret,
  )
})

test("every operation refuses a caller it is not for as denied", async () => {
  let stood = stand()
  let refusals = [
    await called(stood, Nobody, organizations(Open({label: "first"}))),
    await called(stood, Host(1.), organizations(Open({label: "first"}))),
    await called(stood, Host(1.), bindings(Open({organization: 1.}))),
    await called(stood, Operator, bindings(Bind({reach: Tunnel}))),
    await called(stood, Nobody, releases(Put({form: Modules, artifact}))),
    await called(stood, Host(1.), releases(Describe({app: 1.}))),
  ]
  deepEqual(
    refusals->Array.map(((status, answer)) => (status, answer->reason)),
    Array.make(~length=6, (403, Some("denied"))),
  )
  // A host whose binding the control holds nothing of is denied too, as 3d3nt has it.
  deepEqual(
    (await called(stood, Host(9.), bindings(Bind({reach: Tunnel}))))->Pair.second->reason,
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
  let id = opened->data->member("binding")->JSON.Decode.float->Option.getOr(0.)
  deepEqual(
    (status, Envelope.Base64url.decode(secret)->Option.map(TypedArray.length)),
    (200, Some(32)),
  )
  deepEqual(
    (await stood.parts.state.binding(id))->Option.map(b => Envelope.Base64url.encode(b.secret)),
    Some(secret),
  )
})

test("a host bound with no tunnel to make is answered its address alone, again alike", async () => {
  let stood = stand()
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  let id = await openBinding(stood, 1.)
  let (status, bound) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
  let (_, again) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
  deepEqual(
    (status, bound->data),
    (
      200,
      JSON.parseOrThrow(
        `{"binding": ${Float.toString(
            id,
          )}, "reached": {"name": "tunnel", "address": "10.200.0.1"}}`,
      ),
    ),
  )
  deepEqual(again->data, bound->data)
  // A second binding is given the lowest address no binding holds.
  let next = await openBinding(stood, 1.)
  let (_, other) = await called(stood, Host(next), bindings(Bind({reach: Tunnel})))
  deepEqual(other->data->member("reached")->member("address"), JSON.String("10.200.0.2"))
})

/** Tunnels faked, counting what each made. */
let tunnels = (~failing=false, ~unrouted=0) => {
  let made = ref(0)
  let routes = []
  let faked: Tunnels.t = {
    make: async name => {
      made := made.contents + 1
      failing ? Error("the API could not be reached") : Ok(`tunnel-${name}`)
    },
    route: async (~tunnel, ~address) => {
      routes->Array.push((tunnel, address))
      // The first `unrouted` routes asked are refused.
      routes->Array.length <= unrouted ? Error("the route conflicts with another") : Ok()
    },
    token: async tunnel => Ok(`token of ${tunnel}`),
  }
  (faked, made, routes)
}

test(
  "an organization opens a reach, a relayed binding its tunnel made, and no one else may",
  async () => {
    let (faked, _, routes) = tunnels()
    let stood = stand(~tunnels=faked)
    ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
    let (status, opened) = await called(stood, Organization(1.), reaches(Open({})))
    let id = opened->data->member("reach")->JSON.Decode.float->Option.getOr(0.)
    let tunnel = `tunnel-${Api.tunnelName(id)}`
    deepEqual((status, opened->data->member("address")), (200, String("10.200.0.1")))
    deepEqual(
      opened
      ->data
      ->member("tunnel")
      ->JSON.Decode.string
      ->Option.flatMap(Envelope.Base64url.decode)
      ->Option.map(Web.fromUtf8),
      Some(`token of ${tunnel}`),
    )
    deepEqual(routes, [(tunnel, "10.200.0.1")])
    deepEqual((await stood.parts.state.binding(id))->Option.map(b => b.relayed), Some(true))
    deepEqual(
      [
        (await called(stood, Operator, reaches(Open({}))))->Pair.second->reason,
        (await called(stood, Host(id), reaches(Open({}))))->Pair.second->reason,
        (await called(stood, Organization(1.), organizations(Open({label: "second"}))))
        ->Pair.second
        ->reason,
      ],
      [Some("denied"), Some("denied"), Some("denied")],
    )
  },
)

test("a host bound is made one tunnel and one route, and answered the tunnel's token", async () => {
  let (faked, made, routes) = tunnels()
  let stood = stand(~tunnels=faked)
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  let id = await openBinding(stood, 1.)
  let (_, bound) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
  let (_, again) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
  let name = `tunnel-${Api.tunnelName(id)}`
  let tunnel =
    bound
    ->data
    ->member("reached")
    ->member("tunnel")
    ->JSON.Decode.string
    ->Option.flatMap(Envelope.Base64url.decode)
  deepEqual(tunnel->Option.map(Web.fromUtf8), Some(`token of ${name}`))
  // The route is asked on every bind, as its address was taken before it was made.
  deepEqual(
    (made.contents, routes, again->data),
    (1, [(name, "10.200.0.1"), (name, "10.200.0.1")], bound->data),
  )
})

test(
  "a host bound through the control stood on is given its reach once, and again alike",
  async () => {
    let asked = ref(0)
    let standing: Standing.t = {
      reach: async () => {
        asked := asked.contents + 1
        Ok({address: "10.200.0.7", tunnel: Some("token of binding-7")})
      },
    }
    let stood = stand(~standing)
    ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
    let id = await openBinding(stood, 1.)
    let (status, bound) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    let (_, again) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    deepEqual(
      (status, bound->data->member("reached")->member("address")),
      (200, JSON.String("10.200.0.7")),
    )
    deepEqual(
      bound
      ->data
      ->member("reached")
      ->member("tunnel")
      ->JSON.Decode.string
      ->Option.flatMap(Envelope.Base64url.decode)
      ->Option.map(Web.fromUtf8),
      Some("token of binding-7"),
    )
    deepEqual((asked.contents, again->data), (1, bound->data))
  },
)

test("a tunnel the API does not make is unreachable, and no address is kept", async () => {
  let (faked, _, _) = tunnels(~failing=true)
  let stood = stand(~tunnels=faked)
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  let id = await openBinding(stood, 1.)
  let (status, refused) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
  deepEqual((status, refused->reason), (503, Some("unreachable")))
  deepEqual((await stood.parts.state.binding(id))->Option.flatMap(b => b.address), None)
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
    let (status, answer) = await called(stood, Operator, releases(Deploy({binding, release})))
    deepEqual(
      (status, answer->data->member("state")->member("name")),
      (200, JSON.String("running")),
    )
    let app = answer->ranAs->Option.getOr(0.)
    deepEqual(
      await stood.parts.state.deployment(app),
      Some({app, binding, release: hash, capacity: 1.}),
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
    let (_, described) = await called(stood, Operator, releases(Describe({app: app})))
    deepEqual(described->data, answer->data)
  },
)

test(
  "a deploy hands the driver the secrets and network it is given, and none where none",
  async () => {
    let stood = stand()
    let (binding, hash) = await opened(stood)
    let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(32))
    let (_, first) = await called(stood, Operator, releases(Deploy({binding, release})))
    deepEqual(
      stood.host.deployed.contents->Option.map(d => (d.secrets->Dict.keysToArray, d.network)),
      Some(([], [])),
    )
    ignore(
      await called(
        stood,
        Operator,
        releases(
          Deploy({
            binding,
            app: ?(first->ranAs),
            release,
            secrets: dict{"OPERATOR": Web.utf8("kept")},
            network: [Http],
          }),
        ),
      ),
    )
    deepEqual(
      stood.host.deployed.contents->Option.map(d => (
        d.secrets->Dict.get("OPERATOR")->Option.map(Web.fromUtf8),
        d.network,
      )),
      Some((Some("kept"), [Contracts.DeploymentNetwork.Http])),
    )
  },
)

test(
  "a deploy onto a binding not bound, or of a release not kept, is refused before any call",
  async () => {
    let stood = stand()
    ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
    let binding = await openBinding(stood, 1.)
    let release = Uint8Array.fromLength(32)
    let (_, unbound) = await called(stood, Operator, releases(Deploy({binding, release})))
    let (_, none) = await called(stood, Operator, releases(Deploy({binding: 2., release})))
    ignore(await called(stood, Host(binding), bindings(Bind({reach: Tunnel}))))
    let (_, unkept) = await called(stood, Operator, releases(Deploy({binding, release})))
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
  let (status, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
  deepEqual((status, refused->reason), (503, Some("unreachable")))
  stood.host.gone := false
  let app = refused->named
  ok(app != None, ~message="the refusal names the app drawn")
  let (again, answer) = await called(stood, Operator, releases(Deploy({binding, ?app, release})))
  deepEqual((again, answer->ranAs), (200, app))
})

test("a drawn deploy the driver fails names its app, and a retry by it lands there", async () => {
  let stood = stand()
  let (binding, hash) = await opened(stood)
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  // The container is made, and the deploy alone is never answered.
  let failing = ref(true)
  let stood = {
    ...stood,
    parts: {
      ...stood.parts,
      reach: {
        ...stood.host.reach,
        fetch: request =>
          failing.contents && request->Web.url->String.endsWith("/deployments/deploy")
            ? Promise.reject(JsExn.anyToExnInternal("connection reset"))
            : stood.host.reach.fetch(request),
      },
    },
  }
  let (status, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
  let app = refused->named
  deepEqual((status, refused->reason, app != None), (503, Some("unreachable"), true))
  deepEqual(
    (await stood.parts.state.deployment(app->Option.getOr(0.)))->Option.map(d => d.binding),
    Some(binding),
  )
  failing := false
  let (again, answer) = await called(stood, Operator, releases(Deploy({binding, ?app, release})))
  deepEqual((again, answer->ranAs), (200, app))
  // A deploy naming its app is refused with its own message, no app named before it.
  failing := true
  let (_, plain) = await called(stood, Operator, releases(Deploy({binding, ?app, release})))
  deepEqual(plain->named, None)
})

test("a deploy with no app opens a new one, its id drawn, distinct and answered", async () => {
  let stood = stand()
  let (binding, hash) = await opened(stood)
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  let (_, first) = await called(stood, Operator, releases(Deploy({binding, release})))
  let (_, second) = await called(stood, Operator, releases(Deploy({binding, release})))
  let ids = [first, second]->Array.filterMap(ranAs)
  deepEqual(ids->Array.length, 2)
  ok(ids->Array.every(id => id > 0. && id <= 4294967295. && Math.floor(id) == id))
  ok(ids->Array.get(0) != ids->Array.get(1), ~message="each new app is drawn its own id")
  // The id is the driver's too, as the deploy sent it.
  deepEqual(
    stood.host.deployed.contents->Option.map(d => d.runs),
    ids->Array.get(1)->Option.map(id => Contracts.DeploymentRuns.App({id: id})),
  )
  let held = await Promise.all(ids->Array.map(stood.parts.state.deployment))
  deepEqual(held->Array.map(d => d->Option.map(d => d.binding)), [Some(binding), Some(binding)])
})

test(
  "a deploy naming an app redeploys it under its id, and one never deployed is not found",
  async () => {
    let stood = stand()
    let (binding, hash) = await opened(stood)
    let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
    let (_, first) = await called(stood, Operator, releases(Deploy({binding, release})))
    let app = first->ranAs->Option.getOr(0.)
    let (status, again) = await called(stood, Operator, releases(Deploy({binding, app, release})))
    deepEqual((status, again->ranAs), (200, Some(app)))
    let seen = stood.host.seen->Array.length
    let unknown = app == 169552957. ? 169552958. : 169552957.
    let (status, refused) = await called(
      stood,
      Operator,
      releases(Deploy({binding, app: unknown, release})),
    )
    deepEqual(
      (status, refused->reason, refused->member("message")),
      (404, Some("not_found"), JSON.String(`no app ${Ids.text(unknown)} is deployed`)),
    )
    deepEqual(stood.host.seen->Array.length, seen)
    deepEqual(await stood.parts.state.deployment(unknown), None)
  },
)

test(
  "forget removes an app drawn and never run, and refuses one that ran or none held",
  async () => {
    let stood = stand()
    let (binding, hash) = await opened(stood)
    let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
    // A drawn deploy its host never answered leaves an app with no container.
    stood.host.gone := true
    let (_, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
    stood.host.gone := false
    let never = refused->named->Option.getOr(0.)
    let (_, deployed) = await called(stood, Operator, releases(Deploy({binding, release})))
    let ran = deployed->ranAs->Option.getOr(0.)
    let seen = stood.host.seen->Array.length
    let forget = app => releases(Forget({app: app}))
    let (status, forgotten) = await called(stood, Operator, forget(never))
    let refusals = [
      await called(stood, Operator, forget(never)),
      await called(stood, Operator, forget(ran)),
      await called(stood, Operator, forget(4275878552.)),
      await called(stood, Host(binding), forget(ran)),
    ]
    deepEqual(
      (status, forgotten->data),
      (200, JSON.parseOrThrow(`{"app": ${Float.toString(never)}}`)),
    )
    deepEqual(
      refusals->Array.map(((_, answer)) => (
        answer->reason,
        answer->member("message")->JSON.Decode.string->Option.getOr(""),
      )),
      [
        (Some("not_found"), `no app ${Ids.text(never)} is held`),
        (Some("deployed"), `app ${Ids.text(ran)} has run, so it is removed by its own path`),
        (Some("not_found"), "no app fedcba98 is held"),
        (Some("denied"), "The call carries no credential, or one that does not allow it"),
      ],
    )
    // Nothing is asked of the host, and the app that ran is still deployed.
    deepEqual(stood.host.seen->Array.length, seen)
    deepEqual(await stood.parts.state.deployment(never), None)
    ok((await stood.parts.state.deployment(ran))->Option.isSome)
  },
)

test("a range spent is answered as a refusal, to a bind and to a reach alike", async () => {
  let spent = (stood: stood): stood => {
    ...stood,
    parts: {
      ...stood.parts,
      state: {...stood.parts.state, addressed: async (~binding as _, ~address as _=?) => None},
    },
  }
  let (faked, made, routes) = tunnels()
  let answers = []
  let stands = [spent(stand()), spent(stand(~tunnels=faked))]
  for i in 0 to stands->Array.length - 1 {
    let stood = stands->Array.getUnsafe(i)
    ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
    let id = await openBinding(stood, 1.)
    let (status, answer) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    // A bind is told to try again, as a spent range frees when a binding closes.
    answers->Array.push((
      (status, answer->reason),
      (503, Some("unreachable")),
      answer->member("message")->JSON.Decode.string,
      `no address of 10.200.0.0/16 is left for binding ${Ids.text(id)}`,
    ))
    let (status, answer) = await called(stood, Organization(1.), reaches(Open({})))
    answers->Array.push(((status, answer->reason), (400, Some("no_address")), None, ""))
  }
  answers->Array.forEach(((answered, wanted, message, expected)) => {
    deepEqual(answered, wanted)
    message->Option.forEach(m => deepEqual(m, expected))
  })
  // An address is asked before any tunnel is made, so a spent range makes neither.
  deepEqual((made.contents, routes), (0, []))
})

test(
  "a binding's address is the lowest of 10.200.0.0/16 none holds, its first never, as ids gave",
  async () => {
    deepEqual(
      [1, 255, 256, 65535]->Array.map(Addresses.nth),
      ["10.200.0.1", "10.200.0.255", "10.200.1.0", "10.200.255.255"],
    )
    deepEqual(Addresses.lowest([]), Some("10.200.0.1"))
    deepEqual(Addresses.lowest(["10.200.0.1", "10.200.0.3"]), Some("10.200.0.2"))
    deepEqual(
      Addresses.lowest(Array.fromInitializer(~length=Addresses.count, i => Addresses.nth(i + 1))),
      None,
    )
  },
)

/** A request an origin was sent, its URL, its bearer and how it follows a redirect. */
type called = {url: string, authorization: option<string>, redirect: string}

/** How a faked origin answers, `Edge` as Cloudflare's edge does for an origin it cannot reach. */
type answering = Driver | Page | Refusing | Moved | Edge(int) | Silent | Gated(promise<unit>)

let described = () =>
  Host.success(
    Contracts.ManagementDescribed.toJson({generation: 0., policy: 0., grace: 0., items: []}),
  )

/** An origin faked behind the direct fetch, answering as `answering` says and keeping each call. */
let origin = (answering: ref<answering>) => {
  let seen = []
  let direct: Web.fetch = async request => {
    let header = name => request->Web.requestHeaders->Web.header(name)->Nullable.toOption
    seen->Array.push({
      url: request->Web.url,
      authorization: header("authorization"),
      redirect: request->redirectOf,
    })
    switch answering.contents {
    | Driver => described()
    | Gated(gate) =>
      await gate
      described()
    | Page => Web.answered(~status=200, ~contentType="text/html", "<html>Example Domain</html>")
    | Refusing =>
      Host.json(
        403,
        JSON.parseOrThrow(`{"status": "error", "failure": "rejected", "reason": "denied", "message": "no"}`),
      )
    | Moved =>
      Web.response(
        Uint8Array.fromLength(0),
        {status: 302, headers: dict{"location": "http://10.0.0.1/"}},
      )
    | Edge(status) => Web.answered(~status, ~contentType="text/html", "<html>error code</html>")
    | Silent => JsError.throwWithMessage("getaddrinfo ENOTFOUND driver.invalid")
    }
  }
  (direct, seen)
}

/** A stand with an open binding whose origin answers as given, and the binding's id. */
let originStand = async (~tunnels=?, answering) => {
  let (direct, seen) = origin(answering)
  let stood = stand(~tunnels?, ~direct)
  ignore(await called(stood, Operator, organizations(Open({label: "first"}))))
  let id = await openBinding(stood, 1.)
  (stood, seen, id)
}

let byOrigin = origin => bindings(Bind({reach: Origin({origin: origin})}))

let originOf = async (stood, id) =>
  (await stood.parts.state.binding(id))->Option.flatMap(b => b.origin)

let message = json => json->member("message")->JSON.Decode.string->Option.getOr("")

test(
  "an origin the parser refuses, or not https on a DNS name and its default port, is malformed",
  async () => {
    let (stood, seen, id) = await originStand(ref(Driver))
    let refused = [
      "http://driver.example.com",
      "https://192.0.2.10",
      "https://0xc0000210",
      "https://3221226000",
      "https://0300.0.2.10",
      "https://[2001:db8::10]",
      "https://2001:db8::10",
      "https://driver.example.com:8443",
      "https://driver.example.com/management",
      "https://driver.example.com?binding=1",
      "https://admin@driver.example.com",
      "https://driver.example.com#describe",
      "https://localhost",
      "https://driver.localhost",
      "https://printer.local",
      "https://driver.internal",
      "https://router.home.arpa",
      "https://example",
      "https://-driver.example.com",
      "https://driver.example.com.",
      "https://xn--a.example.com",
      "https://xn--ab.example.com",
      "https://xn--99999999999.example.com",
      "https://driver\u0000.example.com",
      "driver.example.com",
    ]
    for i in 0 to refused->Array.length - 1 {
      let given = refused->Array.getUnsafe(i)
      let (status, answer) = await called(stood, Host(id), byOrigin(given))
      deepEqual((status, answer->reason), (400, Some("malformed")), ~message=given)
    }
    deepEqual(seen, [])
    deepEqual(await originOf(stood, id), None)
  },
)

test(
  "an origin is judged as the parser leaves it, punycode and the default port among it",
  async () => {
    let given = [
      ("HTTPS://Driver.Example.com/", "https://driver.example.com"),
      ("https://driver.example.com:443", "https://driver.example.com"),
      ("https://bücher.example.com", "https://xn--bcher-kva.example.com"),
      ("https://xn--bcher-kva.example.com", "https://xn--bcher-kva.example.com"),
    ]
    for i in 0 to given->Array.length - 1 {
      let (text, kept) = given->Array.getUnsafe(i)
      let (stood, seen, id) = await originStand(ref(Driver))
      let (_, bound) = await called(stood, Host(id), byOrigin(text))
      deepEqual(
        (bound->data->member("reached")->member("origin"), seen->Array.map(s => s.url)),
        (JSON.String(kept), [`${kept}/management/describe`]),
        ~message=text,
      )
    }
  },
)

test("an origin proven by its call back is kept and answered", async () => {
  let (stood, seen, id) = await originStand(ref(Driver))
  let (status, bound) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
  deepEqual(
    (status, bound->data),
    (
      200,
      JSON.parseOrThrow(
        `{"binding": ${Float.toString(
            id,
          )}, "reached": {"name": "origin", "origin": "https://driver.example.com"}}`,
      ),
    ),
  )
  let token =
    (await stood.parts.state.binding(id))->Option.map(b =>
      `Bearer ${Access.tokenText(b.id, b.secret)}`
    )
  deepEqual(
    seen,
    [
      {
        url: "https://driver.example.com/management/describe",
        authorization: token,
        redirect: "manual",
      },
    ],
  )
  deepEqual(await originOf(stood, id), Some("https://driver.example.com"))
})

test(
  "an origin that answered and is no driver of the binding is not proven, and not kept",
  async () => {
    let answering = ref(Page)
    let (stood, _, id) = await originStand(answering)
    let answers = []
    [Page, Refusing, Moved, Edge(500), Edge(404)]->Array.forEach(a => answers->Array.push(a))
    let reasons = []
    for i in 0 to answers->Array.length - 1 {
      answering := answers->Array.getUnsafe(i)
      let (status, answer) = await called(stood, Host(id), byOrigin("https://example.com"))
      reasons->Array.push((status, answer->reason, answer->message))
    }
    deepEqual(
      reasons,
      Array.make(
        ~length=5,
        (
          400,
          Some("not_proven"),
          `https://example.com answered, and not as binding ${Ids.text(id)}'s driver`,
        ),
      ),
    )
    deepEqual(await originOf(stood, id), None)
  },
)

test(
  "an origin not answering, or Cloudflare's edge saying so, is unreachable in one message",
  async () => {
    let answering = ref(Silent)
    let (stood, _, id) = await originStand(answering)
    let answers = [Silent, Edge(521), Edge(522), Edge(523), Edge(524), Edge(530)]
    let reasons = []
    for i in 0 to answers->Array.length - 1 {
      answering := answers->Array.getUnsafe(i)
      let (status, answer) = await called(stood, Host(id), byOrigin("https://driver.invalid"))
      reasons->Array.push((status, answer->reason, answer->message))
    }
    deepEqual(
      reasons,
      Array.make(
        ~length=6,
        (
          503,
          Some("unreachable"),
          `https://driver.invalid did not answer binding ${Ids.text(id)}'s call back`,
        ),
      ),
    )
    deepEqual(await originOf(stood, id), None)
  },
)

test("an origin binding's token is spent by its first bind, any bind after it denied", async () => {
  let (stood, seen, id) = await originStand(ref(Driver))
  ignore(await called(stood, Host(id), byOrigin("https://driver.example.com")))
  let again = [
    await called(stood, Host(id), byOrigin("https://driver.example.com")),
    await called(stood, Host(id), byOrigin("https://other.example.com")),
    await called(stood, Host(id), bindings(Bind({reach: Tunnel}))),
  ]
  deepEqual(
    again->Array.map(((status, answer)) => (status, answer->reason)),
    Array.make(~length=3, (403, Some("denied"))),
  )
  deepEqual(
    (seen->Array.length, await originOf(stood, id)),
    (1, Some("https://driver.example.com")),
  )
})

test("two binds by origin at once fix one origin, and the other is denied", async () => {
  let release = ref(() => ())
  let gate = Promise.make((resolve, _) => release := (() => resolve()))
  let (stood, seen, id) = await originStand(ref(Gated(gate)))
  let first = called(stood, Host(id), byOrigin("https://driver.example.com"))
  let second = called(stood, Host(id), byOrigin("https://other.example.com"))
  release.contents()
  let answers = await Promise.all([first, second])
  deepEqual(
    (answers->Array.map(((_, a)) => a->reason), seen->Array.length),
    ([None, Some("denied")], 2),
  )
  deepEqual(await originOf(stood, id), Some("https://driver.example.com"))
})

test(
  "a binding bound by its tunnel is refused an origin as invalid, never called back",
  async () => {
    let (stood, seen, id) = await originStand(ref(Driver))
    ignore(await called(stood, Host(id), bindings(Bind({reach: Tunnel}))))
    let (status, refused) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
    let (_, again) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    deepEqual(
      (
        (status, refused->member("failure"), refused->reason),
        seen,
        await originOf(stood, id),
        again->data->member("reached")->member("name"),
      ),
      ((400, JSON.String("rejected"), Some("invalid")), [], None, JSON.String("tunnel")),
    )
  },
)

test("a binding bound by its origin is called there for every call", async () => {
  let (stood, seen, id) = await originStand(ref(Driver))
  ignore(await called(stood, Host(id), byOrigin("https://driver.example.com")))
  ignore(await called(stood, Operator, releases(Put({form: Modules, artifact}))))
  let release = await Web.sha256(artifact)
  ignore(await called(stood, Operator, releases(Deploy({binding: id, release}))))
  // The bind's call back, then the deploy's own, which the faked origin answers only in part.
  deepEqual(
    seen->Array.slice(~start=0, ~end=3)->Array.map(s => s.url),
    [
      "https://driver.example.com/management/describe",
      "https://driver.example.com/management/describe",
      "https://driver.example.com/management/apply",
    ],
  )
  let token =
    (await stood.parts.state.binding(id))->Option.map(b =>
      `Bearer ${Access.tokenText(b.id, b.secret)}`
    )
  ok(seen->Array.every(s => s.authorization == token), ~message="every call carries the token")
  deepEqual(stood.host.seen, [])
})

test(
  "a direct reach is its origin whatever address and port, its redirects not followed",
  async () => {
    let sent = ref(None)
    let reach = Reach.direct("https://driver.example.com", async request => {
      sent := Some(request->redirectOf)
      Web.answered(~status=200, "")
    })
    deepEqual(reach.origin(~address="10.200.0.1", ~port=37483), "https://driver.example.com")
    ignore(
      await reach.fetch(
        Web.request("https://driver.example.com/x", {method: "GET", headers: dict{}}),
      ),
    )
    deepEqual(sent.contents, Some("manual"))
  },
)

test(
  "a route not made keeps its address unbound, the next binding taking the next and binding",
  async () => {
    let (faked, made, routes) = tunnels(~unrouted=1)
    let (stood, _, id) = await originStand(~tunnels=faked, ref(Driver))
    let (status, refused) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    let kept = (await stood.parts.state.binding(id))->Option.map(b => (b.address, b.bound))
    let next = await openBinding(stood, 1.)
    let (nextStatus, nextBound) = await called(stood, Host(next), bindings(Bind({reach: Tunnel})))
    // Unbound, it is no host to deploy onto, and may still be bound by its origin.
    let release = Uint8Array.fromLength(32)
    let (_, unbound) = await called(stood, Operator, releases(Deploy({binding: id, release})))
    let (bound, answer) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
    deepEqual(
      (
        (status, refused->reason, kept),
        (nextStatus, nextBound->data->member("reached")->member("address")),
        (made.contents, routes),
        unbound->reason,
        (bound, answer->data->member("reached")->member("name")),
      ),
      (
        (503, Some("unreachable"), Some((Some("10.200.0.1"), None))),
        (200, JSON.String("10.200.0.2")),
        (
          2,
          [
            (`tunnel-${Api.tunnelName(id)}`, "10.200.0.1"),
            (`tunnel-${Api.tunnelName(next)}`, "10.200.0.2"),
          ],
        ),
        Some("unbound"),
        (200, JSON.String("origin")),
      ),
    )
  },
)

test(
  "a deploy whose app is forgotten as its container is made is never sent to its host",
  async () => {
    let base = stand()
    base.host.slow := true
    let drawn = ref(0.)
    let caller = ref(None)
    let forgotten = ref(None)
    let state = base.parts.state
    let stood = {
      ...base,
      parts: {
        ...base.parts,
        state: {
          ...state,
          drawApp: async (~random) => {
            drawn := (await state.drawApp(~random))
            drawn.contents
          },
        },
        // The forget lands while the host makes the deploy's container, before it is declared.
        wait: async () =>
          switch (caller.contents, forgotten.contents) {
          | (Some(stood), None) =>
            forgotten :=
              Some(await called(stood, Operator, releases(Forget({app: drawn.contents}))))
          | (Some(_) | None, _) => ()
          },
      },
    }
    caller := Some(stood)
    let (binding, hash) = await opened(stood)
    let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
    let (status, answer) = await called(stood, Operator, releases(Deploy({binding, release})))
    let app = drawn.contents
    deepEqual(
      (
        forgotten.contents->Option.map(((status, _)) => status),
        (status, answer->reason, answer->member("message")->JSON.Decode.string),
        stood.host.deployed.contents,
        await stood.parts.state.deployment(app),
      ),
      (
        Some(200),
        (
          404,
          Some("not_found"),
          Some(`app ${Ids.text(app)}, app ${Ids.text(app)} was forgotten as it was deployed`),
        ),
        None,
        None,
      ),
    )
  },
)

test(
  "a tunnel not made gives its address back, so the binding may still be bound by its origin",
  async () => {
    let (faked, made, routes) = tunnels(~failing=true)
    let (stood, _, id) = await originStand(~tunnels=faked, ref(Driver))
    let (status, refused) = await called(stood, Host(id), bindings(Bind({reach: Tunnel})))
    let kept = (await stood.parts.state.binding(id))->Option.flatMap(b => b.address)
    let (bound, answer) = await called(stood, Host(id), byOrigin("https://driver.example.com"))
    deepEqual(
      (
        (status, refused->reason, kept),
        (made.contents, routes),
        (bound, answer->data->member("reached")->member("name")),
      ),
      ((503, Some("unreachable"), None), (1, []), (200, JSON.String("origin"))),
    )
  },
)
