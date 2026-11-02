open Node
open Grant_fixture

let long = 10000000.

let stood = async () => {
  let t = await make()
  let grant = await mint(t, ~expires=long, ())
  let bytes = fresh()
  let digest = await upload(t, grant, ~bytes, ())
  (t, grant, digest, bytes)
}

let row = async (t, grant, digest) =>
  await Grant_store.staged(t.context.store, grant.proof.grant, Envelope.Hex.encode(digest))

let gone = async (t, grant, digest) => {
  deepEqual(await row(t, grant, digest), None)
  deepEqual(
    t.held->Dict.get(Grant_context.stagingKey(grant.proof.grant, Envelope.Hex.encode(digest))),
    None,
  )
}

/** The control's route over the fixture's database, its clock the wall's, the bytes in a bucket. */
let routed = async () => {
  let t = await make()
  t.time := Date.now()
  let grant = await mint(t, ~expires=t.time.contents +. 86400000., ())
  let bytes = fresh()
  let digest = await upload(t, grant, ~bytes, ())
  let hex = Envelope.Hex.encode(digest)
  let bucket = Routes.bucket()
  await bucket->Stores.put(Grant_context.stagingKey(grant.proof.grant, hex), bytes)
  let env: Stores.env = {state: t.context.store.database, artifacts: bucket, reach: "localhost"}
  let token =
    (await row(t, grant, digest))->Option.getOrThrow->((s: Grant_store.staging) => s.token)
  let get = path =>
    Worker.default.fetch(
      Web.request(`https://control.test${path}`, {method: "GET", headers: dict{}}),
      env,
    )
  (t, grant, hex, token, get)
}

test("a staged read asks the artifact's token and answers no-store", async () => {
  let (_, grant, hex, token, get) = await routed()
  let response = await get(`/artifacts/staging/${grant.proof.grant}/${hex}/${token}`)
  deepEqual(response->Web.status, 200)
  deepEqual(
    response->Web.responseHeaders->Web.header("cache-control")->Nullable.toOption,
    Some("no-store"),
  )
})

test("a staged read is refused without the token, or with another", async () => {
  let (_, grant, hex, token, get) = await routed()
  deepEqual((await get(`/artifacts/staging/${grant.proof.grant}/${hex}`))->Web.status, 404)
  deepEqual((await get(`/artifacts/staging/${grant.proof.grant}/${hex}/`))->Web.status, 404)
  let other = token->String.replaceRegExp(/^./, token->String.startsWith("A") ? "B" : "A")
  deepEqual((await get(`/artifacts/staging/${grant.proof.grant}/${hex}/${other}`))->Web.status, 404)
  deepEqual((await get(`/artifacts/staging/${grant.proof.grant}/${hex}/short`))->Web.status, 404)
})

test("a staged read is refused after expiry", async () => {
  let (t, grant, hex, token, get) = await routed()
  await Grant_store.run(t.context.store, "UPDATE grant_staging SET expires = 1", [])
  deepEqual((await get(`/artifacts/staging/${grant.proof.grant}/${hex}/${token}`))->Web.status, 404)
})

test("a staged read is refused after revocation, the row kept or gone", async () => {
  let (t, grant, hex, token, get) = await routed()
  ignore(await Grant_store.revoke(t.context.store, grant.proof.grant))
  deepEqual((await get(`/artifacts/staging/${grant.proof.grant}/${hex}/${token}`))->Web.status, 404)
  await Grant_store.unstage(t.context.store, grant.proof.grant, hex)
  deepEqual((await get(`/artifacts/staging/${grant.proof.grant}/${hex}/${token}`))->Web.status, 404)
})

test("the token reaches the driver in the address alone", async () => {
  let (t, grant, digest, _) = await stood()
  let token =
    (await row(t, grant, digest))->Option.getOrThrow->((s: Grant_store.staging) => s.token)
  ok(String.length(token) >= 43)
  let uploaded = await call(t, grant.caller, Upload({artifact: fresh(), digest}))
  ok(!(JSON.stringify(Pair.second(uploaded))->String.includes(token)))
  // A second upload keeps the token a driver may be fetching with.
  deepEqual(
    (await row(t, grant, digest))->Option.getOrThrow->((s: Grant_store.staging) => s.token),
    token,
  )
  let deployed = await call(t, grant.caller, Deploy({digest, expected: 0., candidate}))
  deepEqual(deployed->reason, None)
  ok(!(JSON.stringify(Pair.second(deployed))->String.includes(token)))
  let (_, status) = await call(t, grant.caller, Status({}))
  ok(!(JSON.stringify(status)->String.includes(token)))
  let input = t.seen->Array.getUnsafe(0)->Called.member("input")
  deepEqual(
    input->Called.member("artifact")->Called.member("address"),
    JSON.String(
      `https://control.test/artifacts/staging/${grant.proof.grant}/${Envelope.Hex.encode(
          digest,
        )}/${token}`,
    ),
  )
})

test("a recorded deploy deletes its staging once its bytes are copied", async () => {
  let (t, grant, digest, bytes) = await stood()
  deepEqual((await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason, None)
  await gone(t, grant, digest)
  deepEqual(t.held->Dict.get(Envelope.Hex.encode(digest)), Some(bytes))
  // Its replay stays stale though the staging went.
  deepEqual(
    (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("stale"),
  )
})

test("a reconciled deploy copies its bytes before deleting its staging", async () => {
  let (t, grant, digest, bytes) = await stood()
  await lapsed(t, grant, digest)
  let driver = answering(t, async _ => success(digest))
  deepEqual((await call(driver, grant.caller, Status({})))->reason, None)
  await gone(t, grant, digest)
  deepEqual(t.held->Dict.get(Envelope.Hex.encode(digest)), Some(bytes))
})

test("a failure deleting staging leaves a recorded deploy's success", async () => {
  let (t, grant, digest, _) = await stood()
  let refusing = {
    ...t,
    context: {
      ...t.context,
      artifacts: {
        ...t.context.artifacts,
        delete: async _ => JsError.throwWithMessage("the bucket refused"),
      },
    },
  }
  let (answer, lines) = await Grants.logged(() =>
    call(refusing, grant.caller, Deploy({digest, expected: 0., candidate}))
  )
  deepEqual(answer->reason, None)
  deepEqual(lines->Array.length, 1)
  deepEqual(await version(t), 1.)
})

test("revoke deletes that grant's staging, and leaves another grant's", async () => {
  let (t, grant, digest, _) = await stood()
  let other = await mint(t, ~expires=long, ())
  let kept = await upload(t, other, ~bytes=fresh(), ())
  deepEqual((await call(t, Operator, Revoke({grant: grant.proof.grant})))->reason, None)
  await gone(t, grant, digest)
  ok((await row(t, other, kept))->Option.isSome)
})

test("revoke keeps the digest an open intent names until the intent settles", async () => {
  let (t, grant, digest, bytes) = await stood()
  await lapsed(t, grant, digest)
  deepEqual((await call(t, Operator, Revoke({grant: grant.proof.grant})))->reason, None)
  ok((await row(t, grant, digest))->Option.isSome)
  ignore(
    await Grant_lease.reconcile(
      {...t.context, reach: {...t.context.reach, fetch: async _ => success(digest)}},
      app,
    ),
  )
  await gone(t, grant, digest)
  deepEqual(t.held->Dict.get(Envelope.Hex.encode(digest)), Some(bytes))
  deepEqual(await count(t, "grant_audit"), 1)
})

test("retire deletes the staging of every grant of the app", async () => {
  let (t, grant, digest, _) = await stood()
  let other = await mint(t, ~expires=long, ())
  let second = await upload(t, other, ~bytes=fresh(), ())
  deepEqual((await releases(retireDriver(t), Retire({app: app})))->reason, None)
  await gone(t, grant, digest)
  await gone(t, other, second)
})

test("a refused retire keeps the staging", async () => {
  let (t, grant, digest, _) = await stood()
  deepEqual(
    (await releases(retireDriver(t, ~deleteFails=true), Retire({app: app})))->reason,
    Some("still_running"),
  )
  ok((await row(t, grant, digest))->Option.isSome)
})

let expire = async (t, grant, name) => {
  await Grant_store.run(
    t.context.store,
    "INSERT INTO grant_staging (grant, digest, size, expires, token) VALUES (?, ?, 1, 1, 'token')",
    [Text(grant.proof.grant), Text(name)],
  )
  t.held->Dict.set(Grant_context.stagingKey(grant.proof.grant, name), Web.utf8("bytes"))
}

test("mint, revoke and upload each sweep at most 20 expired rows of any grant", async () => {
  let t = await make()
  let grant = await mint(t, ~expires=long, ())
  for i in 1 to 45 {
    await expire(t, grant, `name-${Int.toString(i)}`)
  }
  let other = await mint(t, ~expires=long, ())
  deepEqual(await count(t, "grant_staging"), 25)
  deepEqual(t.held->Dict.keysToArray->Array.length, 25)
  ignore(await upload(t, other, ()))
  deepEqual(await count(t, "grant_staging"), 6)
  deepEqual((await call(t, Operator, Revoke({grant: other.proof.grant})))->reason, None)
  deepEqual(await count(t, "grant_staging"), 0)
  deepEqual(t.held->Dict.keysToArray, [])
})

test("a sweep skips a digest an open intent names, and takes it once settled", async () => {
  let (t, grant, digest, _) = await stood()
  await lapsed(t, grant, digest)
  await Grant_store.run(t.context.store, "UPDATE grant_staging SET expires = 1", [])
  await Grant_staging.sweep(t.context)
  ok((await row(t, grant, digest))->Option.isSome)
  await Grant_store.run(t.context.store, "UPDATE grant_head SET locked = ''", [])
  await Grant_staging.sweep(t.context)
  await gone(t, grant, digest)
})

test("a sweep deletes bytes before the row, so a failed delete leaves the row", async () => {
  let (t, grant, digest, _) = await stood()
  await Grant_store.run(t.context.store, "UPDATE grant_staging SET expires = 1", [])
  let refusing = {
    ...t.context,
    artifacts: {
      ...t.context.artifacts,
      delete: async _ => JsError.throwWithMessage("the bucket refused"),
    },
  }
  let (_, lines) = await Grants.logged(() => Grant_staging.sweep(refusing))
  deepEqual(lines->Array.length, 1)
  ok((await row(t, grant, digest))->Option.isSome)
})

test("an expired row counts toward no grant's room", async () => {
  let t = await make()
  let grant = await mint(t, ~expires=long, ())
  for i in 1 to 25 {
    await expire(t, grant, `name-${Int.toString(i)}`)
  }
  ignore(await upload(t, grant, ()))
})

test("an operator put of a kept hash with another ingress, form or kinds is refused", async () => {
  let t = await make()
  let artifact = fresh()
  let put = (operation: C.ReleasePut.t) => releases(t, Put(operation))
  deepEqual((await put({form: Modules, artifact, kinds: [Function]}))->reason, None)
  let hex = Envelope.Hex.encode(await Web.sha256(artifact))
  let kept = await t.context.state.release(hex)
  deepEqual((await put({form: Modules, artifact, kinds: [Function]}))->reason, None)
  deepEqual((await put({form: Image, artifact, kinds: [Function]}))->reason, Some("invalid"))
  deepEqual((await put({form: Modules, artifact, kinds: [Container]}))->reason, Some("invalid"))
  deepEqual((await put({form: Modules, artifact}))->reason, Some("invalid"))
  deepEqual(
    (
      await put({
        form: Modules,
        artifact,
        kinds: [Function],
        ingress: [Domain({domain: "other.test"})],
      })
    )->reason,
    Some("invalid"),
  )
  deepEqual(await t.context.state.release(hex), kept)
})

test("a deploy grant's app is indexed and the retire trigger reads through it", async () => {
  let plans = []
  let t = await make(~database=Sqlite.database(~plans, ()), ())
  let deploy = await mint(t, ())
  let health = await mint(t, ~health=true, ())
  let rows: array<Grant_store.appId> = (
    await Grant_store.query(
      t.context.store,
      "SELECT app FROM deployment_grant WHERE app IS NOT NULL",
      [],
    )->Stores.all
  ).results
  deepEqual(rows->Array.map((row: Grant_store.appId) => row.app), [app])
  await Grant_store.run(
    t.context.store,
    "UPDATE deployment_grant SET revoked = 1 WHERE app = ?",
    [Number(app)],
  )
  let plan: Sqlite.plan = plans->Array.at(-1)->Option.getOrThrow
  ok(
    plan.rows->Array.some((row: Sqlite.planRow) =>
      row.detail->String.includes("deployment_grant_app")
    ),
    ~message=JSON.stringifyAny(plan.rows)->Option.getOr(""),
  )
  deepEqual(
    (await Grant_store.get(t.context.store, deploy.proof.grant))
    ->Option.getOrThrow
    ->((row: Grant_store.row) => row.revoked),
    1,
  )
  deepEqual(
    (await Grant_store.get(t.context.store, health.proof.grant))
    ->Option.getOrThrow
    ->((row: Grant_store.row) => row.revoked),
    0,
  )
})
