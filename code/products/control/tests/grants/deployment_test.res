open Node
open Grant_fixture

type audit = {grant: string, digest: string, previous: float, version: float, candidate: string}

test(
  "upload stages content by grant and digest and deploy commits increasing versions and audit atomically",
  async () => {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ())
    deepEqual(
      t.held->Dict.keysToArray,
      [Grant_context.stagingKey(grant.proof.grant, Envelope.Hex.encode(digest))],
    )
    let staged =
      (
        await Grant_store.staged(t.context.store, grant.proof.grant, Envelope.Hex.encode(digest))
      )->Option.getOrThrow
    deepEqual(staged.expires, 2000.)
    for i in 0 to 1 {
      if i > 0 {
        ignore(await upload(t, grant, ()))
      }
      let (status, answer) = await call(
        t,
        grant.caller,
        Deploy({digest, expected: Int.toFloat(i), candidate}),
      )
      deepEqual(status, 200, ~message=JSON.stringify(answer))
      let described = answer->Called.data->C.DeploymentGrantDescribed.fromJson->Result.getOrThrow
      deepEqual(
        (described.app, described.version, described.digest, described.candidate),
        (16777236., Int.toFloat(i + 1), digest, candidate),
      )
    }
    deepEqual(await count(t, "grant_audit"), 2)
    let audit: option<audit> = await Grant_store.first(
      t.context.store,
      "SELECT grant, digest, previous, version, candidate FROM grant_audit WHERE app = ? AND version = 2",
      [Number(16777236.)],
    )
    let audit = audit->Option.getOrThrow
    deepEqual(
      (audit.grant, audit.digest, audit.previous, audit.version, audit.candidate),
      (
        grant.proof.grant,
        Envelope.Hex.encode(digest),
        1.,
        2.,
        JSON.stringify(C.DeploymentCandidate.toJson(candidate)),
      ),
    )
    let (_, status) = await call(t, grant.caller, Status({}))
    deepEqual(
      status
      ->Called.data
      ->JSON.Decode.object
      ->Option.getOrThrow
      ->Dict.keysToArray
      ->Array.toSorted(String.compare),
      ["app", "candidate", "digest", "version"],
    )
    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some("stale"),
    )
    deepEqual(t.seen->Array.length, 2)
    for i in 0 to 1 {
      let input = t.seen->Array.getUnsafe(i)->Called.member("input")
      deepEqual(input->Called.member("secrets"), JSON.Null)
      deepEqual(input->Called.member("network"), JSON.Array([String("http")]))
      deepEqual(input->Called.member("into"), JSON.Number(7.))
    }
  },
)

test("staging expires after one hour and cannot be used by another grant", async () => {
  let t = await make()
  let first = await mint(t, ~expires=10000000., ())
  let other = await mint(t, ~expires=10000000., ())
  let digest = await upload(t, first, ())
  deepEqual(
    (await Grant_store.staged(t.context.store, first.proof.grant, Envelope.Hex.encode(digest)))
    ->Option.getOrThrow
    ->((value: Grant_store.staging) => value.expires),
    3601000.,
  )
  deepEqual(
    (await call(t, other.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("not_found"),
  )
  t.time := 3601000.
  deepEqual(
    (await call(t, first.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("not_found"),
  )
  deepEqual(t.seen->Array.length, 0)
})

test(
  "defect 1 revocation during a driver call still commits and audits, as does expiry",
  async () => {
    for i in 0 to 1 {
      let t = await make()
      let grant = await mint(t, ())
      let digest = await upload(t, grant, ())
      t.effect :=
        (
          async () => {
            if i == 0 {
              ignore(await Grant_store.revoke(t.context.store, grant.proof.grant))
            } else {
              t.time := 2000.
            }
          }
        )

      deepEqual(
        (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
        None,
      )
      deepEqual(await count(t, "grant_audit"), 1)
      deepEqual(
        (await Grant_store.head(t.context.store, 16777236.))
        ->Option.getOrThrow
        ->((value: Grant_store.head) => value.version),
        1.,
      )
    }
  },
)

test(
  "expiry after upload refuses before dispatch and concurrent deploys serialize across contexts",
  async () => {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ())
    let concurrent = ref(None)
    t.effect :=
      (
        async () => {
          let separate = {...t, context: {...t.context, origin: t.context.origin}}
          concurrent :=
            Some(await call(separate, grant.caller, Deploy({digest, expected: 0., candidate})))
        }
      )

    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      None,
    )
    deepEqual(concurrent.contents->Option.getOrThrow->reason, Some("stale"))
    deepEqual(t.seen->Array.length, 1)
    t.time := 2000.
    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 1., candidate})))->reason,
      Some("denied"),
    )
    deepEqual(t.seen->Array.length, 1)
  },
)

test("a failed audit insert rolls back the deployment version and digest", async () => {
  let t = await make()
  let grant = await mint(t, ())
  let digest = await upload(t, grant, ())
  await Grant_store.run(
    t.context.store,
    "CREATE TRIGGER audit_refused BEFORE INSERT ON grant_audit BEGIN SELECT RAISE(ABORT, 'audit refused'); END",
    [],
  )
  let answer = await call(t, grant.caller, Deploy({digest, expected: 0., candidate}))
  deepEqual(Pair.first(answer), 503)
  deepEqual(await count(t, "grant_audit"), 0)
  deepEqual(
    (await Grant_store.head(t.context.store, 16777236.))
    ->Option.getOrThrow
    ->((value: Grant_store.head) => value.version),
    0.,
  )
})
