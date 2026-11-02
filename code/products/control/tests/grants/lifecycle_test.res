open Node
open Grant_fixture

test("mint and revoke require the operator and store only the whole bearer verifier", async () => {
  let t = await make()
  let minted = await mint(t, ())
  let row = (await Grant_store.get(t.context.store, minted.proof.grant))->Option.getOrThrow
  deepEqual(row.verifier, Envelope.Hex.encode(await Web.sha256(Web.utf8(minted.bearer))))
  deepEqual(row.policy->String.includes(minted.bearer), false)
  let operations = [
    C.Interface.DeploymentGrants.Mint({policy: Health({expires: 2000.})}),
    Revoke({grant: minted.proof.grant}),
  ]
  let health = await mint(t, ~health=true, ())
  for i in 0 to 1 {
    for j in 0 to 4 {
      let caller =
        [
          Access.Nobody,
          Host(16777226.),
          Organization(1.),
          minted.caller,
          health.caller,
        ]->Array.getUnsafe(j)
      deepEqual((await call(t, caller, operations->Array.getUnsafe(i)))->reason, Some("denied"))
    }
  }
  deepEqual((await call(t, Operator, Revoke({grant: "unknown"})))->reason, Some("not_found"))
  deepEqual((await call(t, Operator, Revoke({grant: minted.proof.grant})))->reason, None)
  deepEqual(await Grant_context.caller(t.context, minted.proof), Access.Nobody)
  deepEqual((await call(t, minted.caller, Status({})))->reason, Some("denied"))
  deepEqual(
    (
      await call(
        t,
        minted.caller,
        Upload({artifact: archive(), digest: await Web.sha256(archive())}),
      )
    )->reason,
    Some("denied"),
  )
})

test(
  "mint bounds expiry to a future safe timestamp and 180 days, and requires an initialized deploy app",
  async () => {
    let t = await make()
    let check = async (policy, expected) =>
      deepEqual((await call(t, Operator, Mint({policy: policy})))->reason, Some(expected))
    await check(Health({expires: 1000.}), "invalid")
    await check(Health({expires: 1000. +. Grant_api.lifetime +. 1.}), "invalid")
    ignore(await mint(t, ~health=true, ~expires=1000. +. Grant_api.lifetime, ()))
    await check(Deploy({app: 999., expires: 2000.}), "not_found")
    await t.context.state.deploy({
      app: 16777236.,
      binding: 16777226.,
      release: (await t.context.state.deployment(16777236.))
      ->Option.getOrThrow
      ->((value: State.deployment) => value.release),
      capacity: 0.,
      kind: None,
    })
    await check(Deploy({app: 16777236., expires: 2000.}), "unbound")
  },
)

test("both live grant caller kinds fail every preexisting control operation", async () => {
  let t = await make()
  let deploy = await mint(t, ())
  let health = await mint(t, ~health=true, ())
  let stood = Called.stand()
  for i in 0 to 1 {
    let caller = [deploy.caller, health.caller]->Array.getUnsafe(i)
    let operations = Grant_gate_test.operations()
    for j in 0 to operations->Array.length - 1 {
      deepEqual(
        (await Called.called(stood, caller, operations->Array.getUnsafe(j)))->reason,
        Some("denied"),
      )
    }
  }
})

test(
  "Access classifies live grants without falling through, and rejects invalid verifiers",
  async () => {
    let t = await make()
    let deploy = await mint(t, ())
    let health = await mint(t, ~health=true, ())
    let caller = bearer =>
      Access.caller(
        Some(`Bearer ${bearer}`),
        ~operator=Some(bearer),
        ~secret=async _ => {
          ok(false)
          None
        },
        ~organizationSecret=async _ => {
          ok(false)
          None
        },
        ~grant=proof => Grant_context.caller(t.context, proof),
      )
    deepEqual(await caller(deploy.bearer), deploy.caller)
    deepEqual(await caller(health.bearer), health.caller)
    deepEqual(
      await caller(
        `dg1.${deploy.proof.grant}.${Envelope.Base64url.encode(Uint8Array.fromLength(32))}`,
      ),
      Nobody,
    )
    deepEqual(await caller("dg1..bad"), Nobody)
    deepEqual(
      await Access.caller(
        Some(`Bearer ${deploy.bearer}`),
        ~operator=Some(deploy.bearer),
        ~secret=async _ => None,
        ~organizationSecret=async _ => None,
        ~grant=async _ => Operator,
      ),
      Nobody,
    )
    t.time := 2000.
    deepEqual(await caller(deploy.bearer), Nobody)
  },
)

test("grant policies and identity callers cannot cross the six operation gates", async () => {
  let t = await make()
  let deploy = await mint(t, ())
  let health = await mint(t, ~health=true, ())
  let nonce = Uint8Array.fromLength(32)
  deepEqual((await call(t, deploy.caller, Health({nonce: nonce})))->reason, Some("denied"))
  let digest = await Web.sha256(archive())
  let ops = [
    C.Interface.DeploymentGrants.Upload({artifact: archive(), digest}),
    Deploy({digest, expected: 0., candidate}),
    Status({}),
  ]
  for i in 0 to 2 {
    deepEqual((await call(t, health.caller, ops->Array.getUnsafe(i)))->reason, Some("denied"))
  }
  for i in 0 to 3 {
    let caller = [Access.Operator, Host(16777226.), Organization(1.), Nobody]->Array.getUnsafe(i)
    deepEqual((await call(t, caller, Health({nonce: nonce})))->reason, Some("denied"))
    for j in 0 to 2 {
      deepEqual((await call(t, caller, ops->Array.getUnsafe(j)))->reason, Some("denied"))
    }
  }
})
