open Node
open Grant_fixture

test("expiry and revocation are rechecked before upload stores any bytes", async () => {
  for i in 0 to 1 {
    let t = await make()
    let grant = await mint(t, ())
    let state = t.context.state
    let changed = {
      ...t,
      context: {
        ...t.context,
        state: {
          ...state,
          deployment: async app => {
            let deployment = await state.deployment(app)
            if i == 0 {
              t.time := 2000.
            } else {
              ignore(await Grant_store.revoke(t.context.store, grant.proof.grant))
            }
            deployment
          },
        },
      },
    }
    deepEqual(
      (
        await call(
          changed,
          grant.caller,
          Upload({artifact: archive(), digest: await Web.sha256(archive())}),
        )
      )->reason,
      Some("denied"),
    )
    deepEqual(t.held->Dict.keysToArray, [])
  }
})

test("operator app mutations share the grant serialization lock", async () => {
  let t = await make()
  let grant = await mint(t, ())
  let digest = await upload(t, grant, ())
  let reached = ref(false)
  t.effect :=
    (
      async () => {
        let answer = await Grant_operator.run(
          ~context=Some(t.context),
          ~app=Some(16777236.),
          async (~mutate as _, ~held as _) => {
            reached := true
            Serve.Calls.Refused({reason: "denied", message: None})
          },
        )
        switch answer {
        | Refused({reason}) => deepEqual(reason, "denied")
        | Output(_) => ok(false)
        }
      }
    )

  deepEqual((await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason, None)
  deepEqual(reached.contents, false)
})

test("driver unavailability and an old driver's malformed refusal never commit", async () => {
  for i in 0 to 1 {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ())
    let changed = {
      ...t,
      context: {
        ...t.context,
        reach: {
          ...t.context.reach,
          fetch: async _ => {
            if i == 0 {
              JsError.throwWithMessage("unreachable")
            } else {
              Web.answered(
                ~status=400,
                ~contentType="application/json",
                "{\"status\":\"error\",\"failure\":\"rejected\",\"reason\":\"malformed\",\"message\":\"secrets required\"}",
              )
            }
          },
        },
      },
    }
    deepEqual(
      (await call(changed, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some(i == 0 ? "unreachable" : "malformed"),
    )
    deepEqual(await count(t, "grant_audit"), 0)
  }
})
