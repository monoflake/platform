open Node
open Grant_fixture

test(
  "health echoes only the nonce and readiness, performs no driver call, and checks every replay",
  async () => {
    let t = await make()
    let grant = await mint(t, ~health=true, ())
    let nonce = Uint8Array.fromLength(32)
    let ready = await call(t, grant.caller, Health({nonce: nonce}))
    deepEqual(Pair.first(ready), 200)
    deepEqual(Pair.second(ready)->Called.data, C.HealthAnswer.toJson({nonce, state: Ready}))
    let unavailable = {
      ...t,
      context: {...t.context, ready: async () => JsError.throwWithMessage("private topology")},
    }
    let answer = await call(unavailable, grant.caller, Health({nonce: nonce}))
    deepEqual(Pair.second(answer)->Called.data, C.HealthAnswer.toJson({nonce, state: Unavailable}))
    deepEqual(JSON.stringify(Pair.second(answer))->String.includes("private topology"), false)
    let uninitialized = {...t, context: {...t.context, initialized: () => false}}
    deepEqual(
      Pair.second(await call(uninitialized, grant.caller, Health({nonce: nonce})))->Called.data,
      C.HealthAnswer.toJson({nonce, state: Unavailable}),
    )
    deepEqual(t.seen->Array.length, 0)
    let wrong = {...t, context: {...t.context, origin: "https://other-control.test"}}
    deepEqual((await call(wrong, grant.caller, Health({nonce: nonce})))->reason, Some("denied"))
    ignore(await call(t, Operator, Revoke({grant: grant.proof.grant})))
    deepEqual((await call(t, grant.caller, Health({nonce: nonce})))->reason, Some("denied"))
  },
)

test("health refuses expiry, a bad verifier, a short nonce and rate overflow", async () => {
  let t = await make()
  let grant = await mint(t, ~health=true, ())
  let nonce = Uint8Array.fromLength(32)
  let bad = Access.HealthGrant({...grant.proof, verifier: Uint8Array.fromLength(32)})
  deepEqual((await call(t, bad, Health({nonce: nonce})))->reason, Some("denied"))
  let json = envelope(Health({nonce: nonce}))
  json
  ->JSON.Decode.object
  ->Option.getOrThrow
  ->Dict.set("input", Object(dict{"nonce": String("00")}))
  deepEqual((await callJson(t, grant.caller, json))->reason, Some("malformed"))
  let limited = ref(false)
  for _ in 0 to 60 {
    let answer = await call(t, grant.caller, Health({nonce: nonce}))
    if answer->reason == Some("denied") {
      limited := true
    }
  }
  ok(limited.contents)
  t.time := 2000.
  deepEqual((await call(t, grant.caller, Health({nonce: nonce})))->reason, Some("denied"))
})
