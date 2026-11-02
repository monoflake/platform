open Node
open Grant_fixture

let long = 10000000.
let unanswered: Web.fetch = async _ => JsError.throwWithMessage("The operation was aborted")
let failure = ((_, json)) => json->Called.member("failure")

let staged = async () => {
  let t = await make()
  let grant = await mint(t, ~expires=long, ())
  let digest = await upload(t, grant, ~bytes=fresh(), ())
  (t, grant, digest)
}

let deployment = async t =>
  (await t.context.state.deployment(app))
  ->Option.getOrThrow
  ->((d: State.deployment) => d.release)

test("an aborted driver call leaves the intent and a later reconcile records it", async () => {
  let (t, grant, digest) = await staged()
  let aborted = answering(t, unanswered)
  deepEqual(
    (await call(aborted, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("unreachable"),
  )
  ok((await locked(t)) != "")
  deepEqual((await version(t), await count(t, "grant_audit")), (0., 0))
  // Within its five minutes the intent holds the app and asks no driver.
  let asked = ref(0)
  let counting = answering(t, async _ => {
    asked := asked.contents + 1
    success(digest)
  })
  deepEqual(
    (await call(counting, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("stale"),
  )
  deepEqual((await call(counting, grant.caller, Status({})))->reason, None)
  deepEqual(asked.contents, 0)
  t.time := t.time.contents +. 300000.
  let (_, status) = await call(counting, grant.caller, Status({}))
  let described = status->Called.data->C.DeploymentGrantDescribed.fromJson->Result.getOrThrow
  deepEqual((described.version, described.digest), (1., digest))
  deepEqual((await count(t, "grant_audit"), await locked(t)), (1, ""))
  let hex = Envelope.Hex.encode(digest)
  deepEqual(await deployment(t), hex)
  ok((await t.context.state.release(hex))->Option.isSome)
  ok(t.held->Dict.get(hex)->Option.isSome)
})

test("a lost answer leaves the intent as an aborted call does", async () => {
  let (t, grant, digest) = await staged()
  let lost = answering(t, async _ =>
    Web.answered(~status=502, ~contentType="text/html", "<html>bad gateway</html>")
  )
  deepEqual(
    (await call(lost, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("bad_answer"),
  )
  ok((await locked(t)) != "")
})

test(
  "a throw while recording leaves the intent, unavailable, and reconcile records it",
  async () => {
    let (t, grant, digest) = await staged()
    await Grant_store.run(
      t.context.store,
      "CREATE TRIGGER audit_refused BEFORE INSERT ON grant_audit BEGIN SELECT RAISE(ABORT, 'audit refused'); END",
      [],
    )
    let answer = await call(t, grant.caller, Deploy({digest, expected: 0., candidate}))
    deepEqual(Pair.first(answer), 503)
    deepEqual(failure(answer), JSON.String("unavailable"))
    ok((await locked(t)) != "")
    deepEqual((await version(t), await count(t, "grant_audit")), (0., 0))
    await Grant_store.run(t.context.store, "DROP TRIGGER audit_refused", [])
    t.time := t.time.contents +. 300000.
    let driver = answering(t, async _ => success(digest))
    deepEqual((await call(driver, grant.caller, Status({})))->reason, None)
    deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (1., 1, ""))
  },
)

test("a throw at reconcile's recording keeps the intent and answers unavailable", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  await Grant_store.run(
    t.context.store,
    "CREATE TRIGGER audit_refused BEFORE INSERT ON grant_audit BEGIN SELECT RAISE(ABORT, 'audit refused'); END",
    [],
  )
  let driver = answering(t, async _ => success(digest))
  let answer = await call(driver, grant.caller, Status({}))
  deepEqual(failure(answer), JSON.String("unavailable"))
  ok((await locked(t)) != "")
  deepEqual((await version(t), await count(t, "grant_audit")), (0., 0))
})

test("the driver not answering at reconcile keeps the intent for a grant caller", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let before = await locked(t)
  let silent = answering(t, unanswered)
  let refused = answering(t, async _ =>
    Web.answered(
      ~status=503,
      ~contentType="application/json",
      "{\"status\":\"error\",\"failure\":\"unavailable\",\"reason\":\"overloaded\",\"message\":\"busy\"}",
    )
  )
  for i in 0 to 1 {
    let driver = i == 0 ? silent : refused
    let status = await call(driver, grant.caller, Status({}))
    deepEqual((Pair.first(status), failure(status)), (503, JSON.String("unavailable")))
    let deployed = await call(driver, grant.caller, Deploy({digest, expected: 0., candidate}))
    deepEqual(failure(deployed), JSON.String("unavailable"))
    deepEqual(await locked(t), before)
  }
  deepEqual((await version(t), await count(t, "grant_audit")), (0., 0))
  ok((await t.context.state.deployment(app))->Option.isSome)
  // The next finder asks again at once, and an answer settles it.
  let driver = answering(t, async _ => success(digest))
  deepEqual((await call(driver, grant.caller, Status({})))->reason, None)
  deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (1., 1, ""))
})

test(
  "a third digest clears with no audit, a log line naming both digests and no secret",
  async () => {
    let (t, grant, digest) = await staged()
    await lapsed(t, grant, digest)
    let third = Uint8Array.fromLength(32)
    let driver = answering(t, async _ => success(third))
    let (answer, lines) = await Grants.logged(() => call(driver, grant.caller, Status({})))
    deepEqual(answer->reason, None)
    deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (0., 0, ""))
    deepEqual(lines->Array.length, 1)
    let line = lines->Array.getUnsafe(0)
    ok(line->String.includes(Envelope.Hex.encode(digest)))
    ok(line->String.includes(Envelope.Hex.encode(third)))
    ok(!(line->String.includes(grant.bearer)))
    ok(!(line->String.includes(grant.proof.grant)))
  },
)

test("a driver that runs nothing clears as a third digest does", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let driver = answering(t, async _ =>
    Web.answered(
      ~status=404,
      ~contentType="application/json",
      "{\"status\":\"error\",\"failure\":\"rejected\",\"reason\":\"not_found\",\"message\":\"none\"}",
    )
  )
  let (answer, lines) = await Grants.logged(() => call(driver, grant.caller, Status({})))
  deepEqual(answer->reason, None)
  deepEqual((await count(t, "grant_audit"), await locked(t), lines->Array.length), (0, "", 1))
})

test("the intent's digest stopped or failed clears, and still making stays", async () => {
  for i in 0 to 1 {
    let (t, grant, digest) = await staged()
    await lapsed(t, grant, digest)
    let state: C.DeploymentState.t = i == 0 ? Stopped : Failed({reason: "bad"})
    let driver = answering(t, async _ => answered(digest, ~state))
    let (answer, _) = await Grants.logged(() => call(driver, grant.caller, Status({})))
    deepEqual(answer->reason, None)
    deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (0., 0, ""))
  }
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let driver = answering(t, async _ => answered(digest, ~state=Making))
  let answer = await call(driver, grant.caller, Status({}))
  deepEqual(failure(answer), JSON.String("unavailable"))
  ok((await locked(t)) != "")
})

test("an intent naming head's digest clears and writes no audit", async () => {
  let t = await make()
  let grant = await mint(t, ~expires=long, ())
  // The fixture's app runs this archive already, so this repeats the running digest.
  let digest = await upload(t, grant, ())
  await lapsed(t, grant, digest)
  let driver = answering(t, async _ => success(digest))
  let (answer, lines) = await Grants.logged(() => call(driver, grant.caller, Status({})))
  deepEqual(answer->reason, None)
  deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (0., 0, ""))
  deepEqual(lines, [])
})

test("a deploy that died before dispatch clears on head's digest and writes no audit", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let head = (await deployment(t))->Envelope.Hex.decode->Option.getOrThrow
  let driver = answering(t, async _ => success(head))
  deepEqual((await call(driver, grant.caller, Status({})))->reason, None)
  deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (0., 0, ""))
})

test("a hold with no digest yet clears asking no driver, as no call followed it", async () => {
  let (t, grant, digest) = await staged()
  let hold = Grant_lease.pending(t.context, "nonce")
  ok(await Grant_store.lock(t.context.store, app, 0., hold))
  t.time := t.time.contents +. 300000.
  let driver = answering(t, async _ => {
    ok(false)
    success(digest)
  })
  deepEqual((await call(driver, grant.caller, Status({})))->reason, None)
  deepEqual(await locked(t), "")
})

test("a stopped or failed state is refused and leaves version and audit unmoved", async () => {
  for i in 0 to 1 {
    let (t, grant, digest) = await staged()
    let state: C.DeploymentState.t = i == 0 ? Stopped : Failed({reason: "bad"})
    let driver = answering(t, async _ => answered(digest, ~state))
    deepEqual(
      (await call(driver, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some("invalid"),
    )
    deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (0., 0, ""))
    deepEqual(await t.context.state.release(Envelope.Hex.encode(digest)), None)
  }
})

test("a making state is no success and leaves the intent", async () => {
  let (t, grant, digest) = await staged()
  let driver = answering(t, async _ => answered(digest, ~state=Making))
  let answer = await call(driver, grant.caller, Deploy({digest, expected: 0., candidate}))
  deepEqual(failure(answer), JSON.String("unavailable"))
  deepEqual((await version(t), await count(t, "grant_audit")), (0., 0))
  ok((await locked(t)) != "")
})

test("an intent written to no row refuses stale before any driver call", async () => {
  let (t, grant, digest) = await staged()
  let state = t.context.state
  // Another holder takes the hold between the lock and the intent.
  let stolen = {
    ...t,
    context: {
      ...t.context,
      state: {
        ...state,
        release: async hash => {
          await Grant_store.run(
            t.context.store,
            "UPDATE grant_head SET locked = 'another' WHERE app = ?",
            [Number(app)],
          )
          await state.release(hash)
        },
      },
    },
  }
  deepEqual(
    (await call(stolen, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
    Some("stale"),
  )
  deepEqual(t.seen->Array.length, 0)
  deepEqual(await locked(t), "another")
})

let operatorDeploy = async t => C.Interface.Releases.Deploy({
  app,
  binding: 16777226.,
  release: (await deployment(t))->Envelope.Hex.decode->Option.getOrThrow,
})

test("an operator deploy records its version bump before its driver call", async () => {
  let t = await make()
  ignore(await mint(t, ()))
  let host = Host.make()
  let seen = ref(None)
  let changed = answering(t, async request => {
    if Web.parts(Web.url(request))->Web.pathname == "/deployments/deploy" {
      seen := Some(await version(t))
    }
    await host.reach.fetch(request)
  })
  deepEqual((await releases(changed, await operatorDeploy(t)))->reason, None)
  deepEqual(seen.contents, Some(1.))
  deepEqual((await version(t), await locked(t), await count(t, "grant_audit")), (1., "", 0))
})

test("an operator deploy with no answer leaves its intent, and reconcile clears it", async () => {
  let t = await make()
  let grant = await mint(t, ~expires=long, ())
  let host = Host.make()
  host.cut := Some("/deployments/deploy")
  let changed = answering(t, host.reach.fetch)
  deepEqual((await releases(changed, await operatorDeploy(t)))->reason, Some("unreachable"))
  deepEqual(await version(t), 1.)
  ok((await locked(t)) != "")
  t.time := t.time.contents +. 300000.
  let digest = (await deployment(t))->Envelope.Hex.decode->Option.getOrThrow
  let driver = answering(t, async _ => success(digest))
  deepEqual((await call(driver, grant.caller, Status({})))->reason, None)
  deepEqual((await version(t), await locked(t), await count(t, "grant_audit")), (1., "", 0))
})

test("an operator refused before any write clears its intent and moves no version", async () => {
  let t = await make()
  ignore(await mint(t, ()))
  let host = Host.make()
  host.gone := true
  let changed = answering(t, host.reach.fetch)
  deepEqual((await releases(changed, await operatorDeploy(t)))->reason, Some("unreachable"))
  deepEqual((await version(t), await locked(t)), (0., ""))
})

test("an operator's driver calls share one deadline shorter than the lease", async () => {
  let t = await make()
  ignore(await mint(t, ()))
  let (answer, asked) = await Grants.deadlines(() => releases(retireDriver(t), Retire({app: app})))
  deepEqual(answer->reason, None)
  deepEqual(asked, [Grant_lease.deadline])
  ok(Int.toFloat(Grant_lease.deadline) < Grant_lease.duration)
})

let overridden = lines =>
  lines->Array.filter(line => line->String.includes("cleared by an operator"))

/** One log line naming the app and the digest and no secret. */
let loggedOnce = (lines, grant, digest) => {
  let found = overridden(lines)
  deepEqual(found->Array.length, 1)
  let line = found->Array.getUnsafe(0)
  ok(line->String.includes(Ids.text(app)))
  ok(line->String.includes(Envelope.Hex.encode(digest)))
  ok(!(line->String.includes(grant.bearer)))
  ok(!(line->String.includes(grant.proof.grant)))
}

/** A driver silent to describe, which is all reconcile asks, and answering the rest as `fetch`. */
let silentToDescribe = (t, fetch: Web.fetch) =>
  answering(t, async request =>
    if Web.parts(Web.url(request))->Web.pathname == "/deployments/describe" {
      await unanswered(request)
    } else {
      await fetch(request)
    }
  )

test("an operator retire with a silent driver and an open intent succeeds and logs", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let driver = silentToDescribe(t, retireDriver(t).context.reach.fetch)
  let (answer, lines) = await Grants.logged(() => releases(driver, Retire({app: app})))
  deepEqual(answer->reason, None)
  deepEqual(await t.context.state.deployment(app), None)
  deepEqual(await count(t, "grant_audit"), 0)
  loggedOnce(lines, grant, digest)
})

test("an operator retire on a dead driver is held by no intent and keeps the app", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let (answer, lines) = await Grants.logged(() =>
    releases(answering(t, unanswered), Retire({app: app}))
  )
  // Rows go only once the driver answers them gone, so the driver's own failure is answered.
  deepEqual(answer->reason, Some("unreachable"))
  ok((await t.context.state.deployment(app))->Option.isSome)
  loggedOnce(lines, grant, digest)
})

test("an operator move off a silent driver with an open intent succeeds and logs", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let state = t.context.state
  let d: State.deployment = (await state.deployment(app))->Option.getOrThrow
  let {organization}: State.binding = (await state.binding(d.binding))->Option.getOrThrow
  let elsewhere = await state.openBinding(
    ~organization,
    ~secret=Uint8Array.fromLength(32),
    ~relayed=false,
    ~random=() => 16777227.,
  )
  ignore(await state.addressed(~binding=elsewhere, ~address="10.200.0.2"))
  await state.routed(~binding=elsewhere)
  let host = Host.make()
  let driver = answering(t, async request =>
    Web.url(request)->String.includes("10.200.0.2")
      ? await host.reach.fetch(request)
      : await unanswered(request)
  )
  let (answer, lines) = await Grants.logged(() =>
    releases(
      driver,
      Deploy({
        app,
        binding: elsewhere,
        release: d.release->Envelope.Hex.decode->Option.getOrThrow,
      }),
    )
  )
  deepEqual(answer->reason, None)
  deepEqual(
    (await state.deployment(app))->Option.getOrThrow->((d: State.deployment) => d.binding),
    elsewhere,
  )
  deepEqual(await locked(t), "")
  deepEqual(await count(t, "grant_audit"), 0)
  loggedOnce(lines, grant, digest)
})

test("an operator forget is held by no intent past its lapse", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let (answer, lines) = await Grants.logged(() =>
    releases(answering(t, unanswered), Forget({app: app}))
  )
  deepEqual(answer->reason, Some("deployed"))
  deepEqual(await locked(t), "")
  loggedOnce(lines, grant, digest)
})

test("an operator overrides a making answer and a throw while recording", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  let making = answering(t, async _ => answered(digest, ~state=Making))
  let (first, lines) = await Grants.logged(() => releases(making, Forget({app: app})))
  deepEqual(first->reason, Some("deployed"))
  loggedOnce(lines, grant, digest)
  await lapsed(t, grant, digest)
  await Grant_store.run(
    t.context.store,
    "CREATE TRIGGER audit_refused BEFORE INSERT ON grant_audit BEGIN SELECT RAISE(ABORT, 'audit refused'); END",
    [],
  )
  let running = answering(t, async _ => success(digest))
  let (second, lines) = await Grants.logged(() => releases(running, Forget({app: app})))
  deepEqual(second->reason, Some("deployed"))
  deepEqual((await version(t), await count(t, "grant_audit"), await locked(t)), (0., 0, ""))
  loggedOnce(lines, grant, digest)
})

test("an intent still in its lease holds an operator as before", async () => {
  let (t, grant, digest) = await staged()
  await lapsed(t, grant, digest)
  t.time := t.time.contents -. 1.
  let (answer, lines) = await Grants.logged(() =>
    releases(answering(t, unanswered), Retire({app: app}))
  )
  deepEqual(answer->reason, Some("denied"))
  ok((await locked(t)) != "")
  deepEqual(overridden(lines), [])
})

test("an app with no head gets no deadline, no head and no lease", async () => {
  let t = await make()
  let host = Host.make()
  let driver = answering(t, host.reach.fetch)
  let deployed = async () => await operatorDeploy(t)
  let operation = await deployed()
  let (answer, asked) = await Grants.deadlines(() => releases(driver, operation))
  deepEqual(answer->reason, None)
  deepEqual(asked, [])
  deepEqual(await count(t, "grant_head"), 0)
  let (retired, asked) = await Grants.deadlines(() => releases(driver, Retire({app: app})))
  deepEqual(retired->reason, None)
  deepEqual(asked, [])
  deepEqual(await t.context.state.deployment(app), None)
})
