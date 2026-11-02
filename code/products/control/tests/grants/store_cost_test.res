open Node
open Grant_fixture

test("grant storage and audit execute on local D1 with measured rows read", async () => {
  let session = await Cost.open_()
  let measurement = Grants.measuring(session)
  let exercise = async () => {
    let t = await make(~database=Grants.database(measurement), ())
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ())
    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      None,
    )
    deepEqual((await call(t, grant.caller, Status({})))->reason, None)
    let health = await mint(t, ~health=true, ())
    deepEqual(
      (await call(t, health.caller, Health({nonce: Uint8Array.fromLength(32)})))->reason,
      None,
    )
    deepEqual((await call(t, Operator, Revoke({grant: grant.proof.grant})))->reason, None)
    deepEqual((await call(t, grant.caller, Status({})))->reason, Some("denied"))
    let maxima = Grants.maxima(measurement)
    ok(maxima->Array.length >= 10)
    maxima->Array.forEach(((sql, rows)) =>
      Console.log(`grant SQL rows_read ${Int.toString(rows)} ${sql}`)
    )
  }
  switch await exercise() {
  | () => await Cost.close(session)
  | exception JsExn(error) =>
    await Cost.close(session)
    throw(JsExn(error))
  }
})
