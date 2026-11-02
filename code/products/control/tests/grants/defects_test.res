open Node
open Grant_fixture

test(
  "defect 2 a lapsed lease with a matching driver records the commit before proceeding",
  async () => {
    let t = await make()
    let grant = await mint(t, ~expires=10000000., ())
    let digest = await upload(t, grant, ~bytes=fresh(), ())
    await lapsed(t, grant, digest)
    let changed = {
      ...t,
      context: {...t.context, reach: {...t.context.reach, fetch: async _ => success(digest)}},
    }
    deepEqual(
      (await call(changed, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some("stale"),
    )
    deepEqual(await version(t), 1.)
    deepEqual(await count(t, "grant_audit"), 1)
    deepEqual(
      (await t.context.state.deployment(app))
      ->Option.getOrThrow
      ->((d: State.deployment) => d.release),
      Envelope.Hex.encode(digest),
    )
    ignore(await upload(t, grant, ~bytes=fresh(), ()))
    deepEqual(
      (await call(changed, grant.caller, Deploy({digest, expected: 1., candidate})))->reason,
      None,
    )
    deepEqual(await count(t, "grant_audit"), 2)
  },
)

test("defect 2 a lapsed lease does not block operator retire", async () => {
  let t = await make()
  let grant = await mint(t, ~expires=10000000., ())
  let digest = await upload(t, grant, ~bytes=fresh(), ())
  await lapsed(t, grant, digest)
  deepEqual((await releases(retireDriver(t), Retire({app: app})))->reason, None)
  deepEqual(await t.context.state.deployment(app), None)
  deepEqual(await count(t, "grant_audit"), 1)
})

test("defect 4 a refused driver call leaves no release row", async () => {
  let t = await make()
  let grant = await mint(t, ())
  let digest = await upload(t, grant, ~bytes=fresh(), ())
  let changed = {
    ...t,
    context: {
      ...t.context,
      reach: {
        ...t.context.reach,
        fetch: async _ =>
          Web.answered(
            ~status=400,
            ~contentType="application/json",
            "{\"status\":\"error\",\"failure\":\"rejected\",\"reason\":\"invalid\",\"message\":\"refused\"}",
          ),
      },
    },
  }
  deepEqual(
    (await call(changed, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("invalid"),
  )
  deepEqual(await t.context.state.release(Envelope.Hex.encode(digest)), None)
  deepEqual(t.held->Dict.get(Envelope.Hex.encode(digest)), None)
  deepEqual(await version(t), 0.)
  deepEqual(await count(t, "grant_audit"), 0)
})

test("defect 4 a conflicting existing release is refused before the driver effect", async () => {
  for i in 0 to 2 {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ~bytes=fresh(), ())
    await t.context.state.putRelease({
      hash: Envelope.Hex.encode(digest),
      form: i == 0 ? Image : Modules,
      size: 1.,
      kinds: i == 1 ? Some([]) : Some([Function]),
      ingress: ?(i == 2 ? Some([]) : None),
    })
    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some("invalid"),
    )
    deepEqual(t.seen->Array.length, 0)
    deepEqual(await version(t), 0.)
  }
})

test("defect 5 a fifth staged artifact is refused and expired bytes are gone", async () => {
  let t = await make()
  let grant = await mint(t, ~expires=10000000., ())
  let digests = []
  for i in 0 to 3 {
    let bytes = archive(~bytes=Web.utf8(`export default {value: ${Int.toString(i)}}`), ())
    digests->Array.push(await upload(t, grant, ~bytes, ()))
  }
  let digest = await Web.sha256(fresh())
  deepEqual(
    (await call(t, grant.caller, Upload({digest, artifact: fresh()})))->reason,
    Some("too_large"),
  )
  deepEqual(await count(t, "grant_staging"), 4)
  deepEqual(t.held->Dict.keysToArray->Array.length, 4)
  t.time := 3601000.
  ignore(await upload(t, grant, ~bytes=fresh(), ()))
  deepEqual(await count(t, "grant_staging"), 1)
  deepEqual(
    t.held->Dict.keysToArray,
    [Grant_context.stagingKey(grant.proof.grant, Envelope.Hex.encode(digest))],
  )
})

test("defect 9 retire revokes every grant bound to the app", async () => {
  let t = await make()
  let first = await mint(t, ())
  let second = await mint(t, ())
  let health = await mint(t, ~health=true, ())
  deepEqual((await releases(retireDriver(t), Retire({app: app})))->reason, None)
  for i in 0 to 1 {
    let grant = [first, second]->Array.getUnsafe(i)
    deepEqual(
      (await Grant_store.get(t.context.store, grant.proof.grant))
      ->Option.getOrThrow
      ->((row: Grant_store.row) => row.revoked),
      1,
    )
  }
  deepEqual(
    (await Grant_store.get(t.context.store, health.proof.grant))
    ->Option.getOrThrow
    ->((row: Grant_store.row) => row.revoked),
    0,
  )
})

test(
  "defect 7 an operator stop followed by a failed delete invalidates grant expected",
  async () => {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ~bytes=fresh(), ())
    deepEqual(
      (await releases(retireDriver(t, ~deleteFails=true), Retire({app: app})))->reason,
      Some("still_running"),
    )
    deepEqual(await version(t), 1.)
    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some("stale"),
    )
  },
)

test("defect 6 dispatch uses the deployment and binding refreshed after locking", async () => {
  let t = await make()
  let grant = await mint(t, ())
  let digest = await upload(t, grant, ~bytes=fresh(), ())
  let reads = ref(0)
  let origins = []
  let state = t.context.state
  let changed = {
    ...t,
    context: {
      ...t.context,
      state: {
        ...state,
        deployment: async app => {
          reads := reads.contents + 1
          (await state.deployment(app))->Option.map(d =>
            reads.contents > 1 ? {...d, capacity: 9.} : d
          )
        },
        binding: async id =>
          (await state.binding(id))->Option.map(b =>
            reads.contents > 1 ? {...b, origin: Some("https://fresh.test")} : b
          ),
      },
      direct: async request => {
        origins->Array.push(Web.parts(Web.url(request))->Web.origin)
        await t.context.reach.fetch(request)
      },
    },
  }
  deepEqual(
    (await call(changed, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
    None,
  )
  deepEqual(origins, ["https://fresh.test"])
  deepEqual(
    t.seen->Array.getUnsafe(0)->Called.member("input")->Called.member("into"),
    JSON.Number(9.),
  )
})

test(
  "defect 7 an operator deployment row written before a refusal invalidates expected",
  async () => {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ~bytes=fresh(), ())
    let host = Host.make()
    host.cut := Some("/deployments/deploy")
    let changed = {...t, context: {...t.context, reach: host.reach}}
    let refused = await releases(
      changed,
      Deploy({
        app,
        binding: 16777226.,
        release: (await t.context.state.deployment(app))
        ->Option.getOrThrow
        ->((d: State.deployment) => Envelope.Hex.decode(d.release)->Option.getOrThrow),
      }),
    )
    ok(refused->reason->Option.isSome)
    deepEqual(await version(t), 1.)
    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some("stale"),
    )
  },
)

test(
  "defect 2 failed unlock and post dispatch lookups preserve a committed answer and free the lease",
  async () => {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ~bytes=fresh(), ())
    let failed = ref(false)
    t.effect := (async () => failed := true)
    let state = t.context.state
    let changed = {
      ...t,
      context: {
        ...t.context,
        store: {
          ...t.context.store,
          database: Sqlite.refusing(t.context.store.database, "UPDATE grant_head SET locked = ''"),
        },
        state: {
          ...state,
          deployment: async app => {
            if failed.contents {
              JsError.throwWithMessage("lookup refused")
            }
            await state.deployment(app)
          },
        },
      },
    }
    deepEqual(
      (await call(changed, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      None,
    )
    deepEqual(await version(t), 1.)
    deepEqual(await count(t, "grant_audit"), 1)
    deepEqual(await locked(t), "")
  },
)
