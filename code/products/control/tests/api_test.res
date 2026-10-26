/***
 * The API held to RFC rxmd9 with its parts in memory and a host faked, each operation answering
 * its own caller alone and passing on what the host's driver answered.
 */
open Node
open Called

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
      Some({app, binding, release: hash, capacity: 1., kind: Some(Function)}),
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
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  // Not answering its describe, the host is unreachable before any app is drawn.
  stood.host.gone := true
  let (status, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
  deepEqual((status, refused->reason, refused->named), (503, Some("unreachable"), None))
  stood.host.gone := false
  stood.host.cut := Some("/management/apply")
  let (status, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
  deepEqual((status, refused->reason), (503, Some("unreachable")))
  stood.host.cut := None
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
    // A drawn deploy whose container its host never answered leaves an app with no container.
    stood.host.cut := Some("/management/apply")
    let (_, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
    stood.host.cut := None
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
        (Some("deployed"), `app ${Ids.text(ran)} has run, so it is removed by retire`),
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

/** The states the API keeps, each fresh, in memory, in D1 and over objects. */
let kept = () => {
  let sealing = Sealing.ofKey(Some(Envelope.Base64url.encode(Web.random(32))))
  let held: dict<Uint8Array.t> = dict{}
  let objects: Objects.t = {
    write: async (name, bytes) => Ok(held->Dict.set(name, bytes)),
    read: async name => Ok(held->Dict.get(name)),
    list: async prefix => Ok(
      held
      ->Dict.keysToArray
      ->Array.filter(n => n->String.startsWith(prefix))
      ->Array.toSorted(String.compare),
    ),
    delete: async name => Ok(held->Dict.delete(name)),
  }
  [
    ("memory", Memory.state()),
    ("D1", State.ofDatabase(Sqlite.database(), ~sealing)),
    ("objects", State.ofObjects(objects, ~sealing)),
  ]
}

/** A control standing over a state, an app that ran on it and one drawn that never ran. */
let ranAndNever = async state => {
  let stood = stand()
  let stood = {...stood, parts: {...stood.parts, state}}
  let (binding, hash) = await opened(stood)
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  stood.host.cut := Some("/management/apply")
  let (_, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
  stood.host.cut := None
  let never = refused->named->Option.getOr(0.)
  let (_, deployed) = await called(stood, Operator, releases(Deploy({binding, release})))
  (stood, binding, release, deployed->ranAs->Option.getOr(0.), never)
}

/** The paths asked of the host since a count of what it was asked. */
let askedSince = (stood, seen) =>
  stood.host.seen
  ->Array.slice(~start=seen)
  ->Array.map(s => Web.parts(s.url)->Web.pathname)

/** A refusal's reason and message. */
let refusal = ((_, answer)) => (
  answer->reason,
  answer->member("message")->JSON.Decode.string->Option.getOr(""),
)

test("retire stops then deletes an app that ran, and only then removes its rows", async () => {
  let states = kept()
  for i in 0 to states->Array.length - 1 {
    let (name, state) = states->Array.getUnsafe(i)
    let (stood, binding, release, ran, _) = await ranAndNever(state)
    let seen = stood.host.seen->Array.length
    let (status, retired) = await called(stood, Operator, releases(Retire({app: ran})))
    deepEqual(
      (status, retired->data),
      (200, JSON.parseOrThrow(`{"app": ${Float.toString(ran)}}`)),
      ~message=name,
    )
    deepEqual(askedSince(stood, seen), ["/deployments/stop", "/deployments/delete"], ~message=name)
    deepEqual((await state.deployment(ran), await state.hasApp(ran)), (None, false), ~message=name)
    // A deploy naming it afterwards finds no app and asks no driver.
    let seen = stood.host.seen->Array.length
    let again = await called(stood, Operator, releases(Deploy({binding, app: ran, release})))
    deepEqual(
      (again->refusal, stood.host.seen->Array.length),
      ((Some("not_found"), `no app ${Ids.text(ran)} is deployed`), seen),
      ~message=name,
    )
    deepEqual(
      (await called(stood, Operator, releases(Retire({app: ran}))))->refusal,
      (Some("not_found"), `no app ${Ids.text(ran)} is held`),
      ~message=name,
    )
  }
})

test(
  "retire refuses an app that never ran, an id not held, and every caller but the operator",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let (stood, binding, _, ran, never) = await ranAndNever(state)
      let seen = stood.host.seen->Array.length
      let bare = await state.drawApp(~random=() => 4275878551.)
      let retire = app => releases(Retire({app: app}))
      let refusals = [
        await called(stood, Operator, retire(never)),
        await called(stood, Operator, retire(bare)),
        await called(stood, Operator, retire(4275878552.)),
        await called(stood, Host(binding), retire(ran)),
        await called(stood, Organization(1.), retire(ran)),
      ]
      deepEqual(
        refusals->Array.map(refusal),
        [
          (Some("not_deployed"), `app ${Ids.text(never)} never ran, so it is removed by forget`),
          (Some("not_deployed"), "app fedcba97 never ran, so it is removed by forget"),
          (Some("not_found"), "no app fedcba98 is held"),
          (Some("denied"), "The call carries no credential, or one that does not allow it"),
          (Some("denied"), "The call carries no credential, or one that does not allow it"),
        ],
        ~message=name,
      )
      // Nothing is asked of the host, and every app is still held.
      deepEqual(stood.host.seen->Array.length, seen, ~message=name)
      deepEqual(
        (
          (await state.deployment(never))->Option.map(d => d.capacity),
          await state.hasApp(bare),
          (await state.deployment(ran))->Option.isSome,
        ),
        (Some(0.), true, true),
        ~message=name,
      )
    }
  },
)

test(
  "retire of an app whose driver is not reached is unreachable and removes nothing",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let (stood, _, _, ran, _) = await ranAndNever(state)
      stood.host.gone := true
      let (status, answer) = await called(stood, Operator, releases(Retire({app: ran})))
      deepEqual((status, answer->reason), (503, Some("unreachable")), ~message=name)
      deepEqual(
        ((await state.deployment(ran))->Option.isSome, await state.hasApp(ran)),
        (true, true),
        ~message=name,
      )
      // Retired once the driver answers again.
      stood.host.gone := false
      let (status, _) = await called(stood, Operator, releases(Retire({app: ran})))
      deepEqual((status, await state.deployment(ran)), (200, None), ~message=name)
    }
  },
)

test("retire takes a driver answering not_found as the deployment gone already", async () => {
  let states = kept()
  for i in 0 to states->Array.length - 1 {
    let (name, state) = states->Array.getUnsafe(i)
    let (stood, _, _, ran, _) = await ranAndNever(state)
    stood.host.lost := true
    let seen = stood.host.seen->Array.length
    let (status, _) = await called(stood, Operator, releases(Retire({app: ran})))
    deepEqual(
      (status, askedSince(stood, seen)),
      (200, ["/deployments/stop", "/deployments/delete"]),
      ~message=name,
    )
    deepEqual((await state.deployment(ran), await state.hasApp(ran)), (None, false), ~message=name)
  }
})

test("retire passes on a delete the driver refused, and removes nothing", async () => {
  let stood = stand()
  // A driver whose stop leaves the deployment running, as one past its grace would.
  let reach = stood.host.reach
  let stubborn: Reach.t = {
    ...reach,
    fetch: async request =>
      Web.parts(request->Web.url)->Web.pathname == "/deployments/stop"
        ? Host.success(
            Contracts.DeploymentDescribed.toJson({
              runs: App({id: 1.}),
              version: Uint8Array.fromLength(32),
              state: Making,
            }),
          )
        : await reach.fetch(request),
  }
  let stood = {...stood, parts: {...stood.parts, reach: stubborn}}
  let (binding, hash) = await opened(stood)
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  let (_, deployed) = await called(stood, Operator, releases(Deploy({binding, release})))
  let ran = deployed->ranAs->Option.getOr(0.)
  let (status, answer) = await called(stood, Operator, releases(Retire({app: ran})))
  deepEqual(
    (status, answer->member("failure")->JSON.Decode.string, (status, answer)->refusal),
    (400, Some("rejected"), (Some("still_running"), "it runs")),
  )
  ok((await stood.parts.state.deployment(ran))->Option.isSome)
})

test("retire of an app whose binding is not held is unreachable and removes nothing", async () => {
  // D1's foreign key keeps every deployment's binding, so only memory and objects can lose one.
  let states = kept()->Array.filter(((name, _)) => name != "D1")
  for i in 0 to states->Array.length - 1 {
    let (name, state) = states->Array.getUnsafe(i)
    let stood = stand()
    let stood = {...stood, parts: {...stood.parts, state}}
    let app = await state.drawApp(~random=() => 4275878551.)
    await state.deploy({app, binding: 4275878552., release: "aa", capacity: 1., kind: None})
    let (status, answer) = await called(stood, Operator, releases(Retire({app: app})))
    deepEqual(
      (status, answer->member("failure")->JSON.Decode.string, (status, answer)->refusal),
      (
        503,
        Some("unavailable"),
        (
          Some("unreachable"),
          "app fedcba97 runs on binding fedcba98, which is not held, so no driver is asked",
        ),
      ),
      ~message=name,
    )
    deepEqual(
      (stood.host.seen, (await state.deployment(app))->Option.isSome, await state.hasApp(app)),
      ([], true, true),
      ~message=name,
    )
  }
})

/** A release put with the kinds it declares, its artifact its own, and its hash in hex. */
let putKinds = async (stood, text, kinds) => {
  let (_, put) = await called(
    stood,
    Operator,
    releases(Put({form: Modules, artifact: Web.utf8(text), ?kinds})),
  )
  put->data->member("hash")->JSON.Decode.string->Option.getOr("")
}

let bytesOf = hex => Envelope.Hex.decode(hex)->Option.getOr(Uint8Array.fromLength(0))

/** A control whose state counts the apps it draws and the deployments it writes. */
let watched = stood => {
  let (draws, writes) = (ref(0), ref(0))
  let state = stood.parts.state
  let counted = {
    ...state,
    drawApp: (~random) => {
      draws := draws.contents + 1
      state.drawApp(~random)
    },
    deploy: d => {
      writes := writes.contents + 1
      state.deploy(d)
    },
  }
  ({...stood, parts: {...stood.parts, state: counted}}, draws, writes)
}

test(
  "a modules release with no kinds on a machine binding asks the list and deploy it asked before",
  async () => {
    let described = [Some([Contracts.ManagementKind.Function, Container, Object, Volume]), None]
    for i in 0 to described->Array.length - 1 {
      let kinds = described->Array.getUnsafe(i)
      let stood = stand()
      stood.host.kinds := kinds
      let (binding, hash) = await opened(stood)
      let release = bytesOf(hash)
      let (status, answer) = await called(stood, Operator, releases(Deploy({binding, release})))
      let app = answer->ranAs->Option.getOr(0.)
      // The list and the deploy the control sent before kinds were matched, emgxf.
      let credentials =
        stood.host.applied.contents->Option.mapOr([], l =>
          l.items->Array.flatMap(i => i.credentials)
        )
      deepEqual(
        stood.host.applied.contents->Option.map(l =>
          JSON.stringify(Contracts.ManagementApply.toJson(l))
        ),
        Some(
          JSON.stringify(
            Contracts.ManagementApply.toJson({
              generation: 1.,
              items: [{id: 1., capacity: Deploying.capacity, credentials}],
            }),
          ),
        ),
      )
      deepEqual(credentials->Array.map(TypedArray.length), [32])
      deepEqual(
        stood.host.deployed.contents->Option.map(d =>
          JSON.stringify(Contracts.DeploymentDeploy.toJson(d))
        ),
        Some(
          JSON.stringify(
            Contracts.DeploymentDeploy.toJson({
              runs: App({id: app}),
              version: release,
              form: Modules,
              isolation: [Isolate],
              artifact: {address: `https://control.test/artifacts/${hash}`, hash: release},
              footing: "https://footing.invalid",
              secrets: dict{},
              network: [],
              into: 1.,
            }),
          ),
        ),
      )
      deepEqual(
        (status, stood.host.seen->Array.map(s => Web.parts(s.url)->Web.pathname)),
        (
          200,
          [
            "/management/describe",
            "/management/apply",
            "/management/describe",
            "/deployments/deploy",
          ],
        ),
      )
      deepEqual(
        await stood.parts.state.deployment(app),
        Some({app, binding, release: hash, capacity: 1., kind: Some(Function)}),
      )
    }
  },
)

test(
  "a function on a binding offering no container is deployed into none, and has run",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let stood = stand()
      let stood = {...stood, parts: {...stood.parts, state}}
      stood.host.kinds := Some([Function, Object])
      let (binding, hash) = await opened(stood)
      let (status, answer) = await called(
        stood,
        Operator,
        releases(Deploy({binding, release: bytesOf(hash)})),
      )
      let app = answer->ranAs->Option.getOr(0.)
      deepEqual(
        (
          status,
          stood.host.seen->Array.map(s => Web.parts(s.url)->Web.pathname),
          stood.host.applied.contents,
          stood.host.deployed.contents->Option.map(d => d.into),
          await state.deployment(app),
        ),
        (
          200,
          ["/management/describe", "/deployments/deploy"],
          None,
          Some(None),
          Some({app, binding, release: hash, capacity: 0., kind: Some(Function)}),
        ),
        ~message=name,
      )
      deepEqual(
        (await called(stood, Operator, releases(Forget({app: app}))))->refusal,
        (Some("deployed"), `app ${Ids.text(app)} has run, so it is removed by retire`),
        ~message=name,
      )
      let seen = stood.host.seen->Array.length
      let (status, _) = await called(stood, Operator, releases(Retire({app: app})))
      deepEqual(
        (status, askedSince(stood, seen), await state.deployment(app), await state.hasApp(app)),
        (200, ["/deployments/stop", "/deployments/delete"], None, false),
        ~message=name,
      )
    }
  },
)

test(
  "a release sharing no kind with its binding is beyond its host, and draws nothing",
  async () => {
    let (stood, draws, writes) = watched(stand())
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "a function", Some([Function]))
    stood.host.kinds := Some([Container, Object])
    let (status, answer) = await called(
      stood,
      Operator,
      releases(Deploy({binding, release: bytesOf(hash)})),
    )
    deepEqual(
      (
        (status, answer)->refusal,
        draws.contents,
        writes.contents,
        stood.host.seen->Array.map(s => Web.parts(s.url)->Web.pathname),
      ),
      (
        (
          Some("beyond_host"),
          `release ${hash} runs as function, and binding ${Ids.text(
              binding,
            )} offers container, object`,
        ),
        0,
        0,
        ["/management/describe"],
      ),
    )
    deepEqual(status, 400)
  },
)

test("a redeploy of a release its binding no longer runs changes nothing it holds", async () => {
  let stood = stand()
  let (binding, hash) = await opened(stood)
  let release = bytesOf(hash)
  let (_, first) = await called(stood, Operator, releases(Deploy({binding, release})))
  let app = first->ranAs->Option.getOr(0.)
  let held = await stood.parts.state.deployment(app)
  stood.host.kinds := Some([Container])
  let (stood, draws, writes) = watched(stood)
  let again = await called(stood, Operator, releases(Deploy({binding, app, release})))
  deepEqual(
    (again->refusal, draws.contents, writes.contents),
    (
      (
        Some("beyond_host"),
        `release ${hash} runs as function, and binding ${Ids.text(binding)} offers container`,
      ),
      0,
      0,
    ),
  )
  deepEqual(await stood.parts.state.deployment(app), held)
})

test(
  "a release declaring instance alone is beyond every binding, one offering it too",
  async () => {
    let stood = stand()
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "an instance", Some([Instance]))
    let deployed = async kinds => {
      stood.host.kinds := kinds
      let answer = await called(
        stood,
        Operator,
        releases(Deploy({binding, release: bytesOf(hash)})),
      )
      answer->refusal
    }
    let named = Ids.text(binding)
    deepEqual(
      (await deployed(Some([Function, Instance, Container])), await deployed(None)),
      (
        (
          Some("beyond_host"),
          `release ${hash} runs as instance, which this control deploys onto no binding yet`,
        ),
        (
          Some("beyond_host"),
          `release ${hash} runs as instance, and binding ${named} offers function, container`,
        ),
      ),
    )
    deepEqual(stood.host.deployed.contents, None)
  },
)

test(
  "a release declaring an empty list of kinds is beyond every binding, and draws nothing",
  async () => {
    let (stood, draws, writes) = watched(stand())
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "no kinds", Some([]))
    let (status, answer) = await called(
      stood,
      Operator,
      releases(Deploy({binding, release: bytesOf(hash)})),
    )
    deepEqual(
      ((status, answer)->refusal, status, draws.contents, writes.contents),
      ((Some("beyond_host"), `release ${hash} declares no kind it runs as`), 400, 0, 0),
    )
  },
)

test(
  "the first of a release's kinds its binding offers is chosen, in the release's order",
  async () => {
    let stood = stand()
    stood.host.kinds := Some([Function, Container])
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "a container first", Some([Container, Function]))
    let (status, answer) = await called(
      stood,
      Operator,
      releases(Deploy({binding, release: bytesOf(hash)})),
    )
    let app = answer->ranAs->Option.getOr(0.)
    deepEqual(
      (
        status,
        await stood.parts.state.deployment(app),
        stood.host.deployed.contents->Option.map(d => d.into),
      ),
      (
        200,
        Some({app, binding, release: hash, capacity: 1., kind: Some(Container)}),
        Some(Some(1.)),
      ),
    )
  },
)

test(
  "a release keeps the kinds it was put with, a second put of its hash changing nothing",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let stood = stand()
      let stood = {...stood, parts: {...stood.parts, state}}
      let ordered = await putKinds(stood, "ordered", Some([Container, Function]))
      let again = await putKinds(stood, "ordered", None)
      let empty = await putKinds(stood, "empty", Some([]))
      let none = await putKinds(stood, "none", None)
      let kindsOf = async hash => (await state.release(hash))->Option.map(r => r.kinds)
      deepEqual(
        (again == ordered, await kindsOf(ordered), await kindsOf(empty), await kindsOf(none)),
        (
          true,
          Some(Some([Contracts.DeploymentKind.Container, Function])),
          Some(Some([])),
          Some(None),
        ),
        ~message=name,
      )
    }
  },
)
