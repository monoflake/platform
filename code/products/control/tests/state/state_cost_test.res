/** Each state statement is measured against the model on growing local D1 fixtures. */
open Node
open Stored

let fixture = async (session, n) => {
  let exec = sql => Cost.exec(session, sql)
  await exec(
    "INSERT INTO organization (id, label, secret) VALUES (1, 'first', '" ++
    Envelope.Hex.encode(secret) ++ "')",
  )
  if n > 0 {
    let counted = `WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n
      WHERE v < ${Int.toString(n)})`
    await exec(
      `${counted} INSERT INTO organization (id, label, secret)
      SELECT v + 1000, 'organization-' || v, '${Envelope.Hex.encode(secret)}' FROM n`,
    )
    await exec(
      `${counted} INSERT INTO binding (id, organization, secret, address, bound)
      SELECT v + 2000, 1, '${Envelope.Hex.encode(secret)}',
      '10.200.' || (v / 256) || '.' || (v % 256), v FROM n`,
    )
    await exec(
      `${counted} INSERT INTO release (hash, form, size)
      SELECT 'release-' || v, 'modules', 3 FROM n`,
    )
    await exec(`${counted} INSERT INTO app (id) SELECT v + 3000 FROM n`)
    await exec(
      `${counted} INSERT INTO deployment (app, binding, release, capacity)
      SELECT v + 3000, v + 2000, 'release-' || v, 1 FROM n`,
    )
    // These ids make the next organization step past a dense run of held ids.
    await exec(`${counted} INSERT INTO app (id) SELECT v + ${Int.toString(n + 1000)} FROM n`)
  }
}

let exercise = async session => {
  let database = session->Cost.database
  let state = State.ofDatabase(database, ~sealing=Sealing.ofKey(key))
  let exec = sql => Cost.exec(session, sql)
  ignore(await state.openOrganization("first", ~secret))
  let organization = await state.openOrganization("second", ~secret)
  ignore(await state.hasOrganization(organization.id))
  ignore(await state.hasOrganization(999999.))
  ignore(await state.organizationSecret(1.))
  let binding = await state.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() =>
    4275878552.
  )
  // Reading a plain binding measures the other table's secret write back.
  await exec(
    `INSERT INTO binding (id, organization, secret)
    VALUES (4000000, 1, '${Envelope.Hex.encode(secret)}')`,
  )
  ignore(await state.binding(4000000.))
  ignore(await state.binding(999999.))
  ignore(await state.addressed(~binding))
  ignore(await state.addressed(~binding))
  ignore(await state.addressed(~binding=999999.))
  ignore(await state.addressed(~binding=4000000., ~address="10.200.255.254"))
  await state.unaddressed(~binding=4000000., ~address="10.200.255.254")
  await state.tunneled(~binding, ~tunnel="fixture")
  await state.routed(~binding)
  ignore(await state.storage(1.))
  ignore(await state.storage(999999.))
  ignore(await state.addressedAt("10.200.255.253"))
  ignore(await state.originated(~binding=4000000., ~origin="https://driver.example.com"))
  await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
  await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
  ignore(await state.release("aa"))
  ignore(await state.release("missing"))
  let app = await state.drawApp(~random=() => 4275878553.)
  await exec(
    "INSERT INTO organization (id, label, secret)
    VALUES (16909060, 'collision', '" ++
    Envelope.Hex.encode(secret) ++ "')",
  )
  ignore(await state.drawApp(~random=scripted(list{binding, 16909060., app, 4275878555.})))
  ignore(
    await state.openBinding(
      ~organization=1.,
      ~secret,
      ~relayed=false,
      ~random=scripted(list{binding, 16909060., app, 4275878556.}),
    ),
  )
  let deployment: State.deployment = {app, binding, release: "aa", capacity: 0., kind: None}
  await state.deploy(deployment)
  await state.deploy(deployment)
  ignore(await state.deployment(app))
  ignore(await state.hasApp(app))
  ignore(await state.forgetApp(app))
  // A deployment kept without its app reaches the final held check during forget.
  await exec(
    `INSERT INTO deployment (app, binding, release, capacity)
    VALUES (4000001, ${Float.toString(binding)}, 'aa', 0)`,
  )
  ignore(await state.forgetApp(4000001.))
  ignore(await state.drawApp(~random=() => 4275878553.))
  await state.deploy({...deployment, capacity: 1.})
  await state.retireApp(app)
  // A refused secret update reaches the binding cleanup statement.
  let refused = State.ofDatabase(
    Sqlite.refusing(database, "UPDATE binding SET secret"),
    ~sealing=Sealing.ofKey(key),
  )
  ok(
    (
      await thrown(() =>
        refused.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() => 4275878554.)
      )
    )->Option.isSome,
  )
}

test("every state statement stays within its rows read budget", async () => {
  let session = await Cost.open_()
  try {
    let sizes = session->Cost.sizes
    for i in 0 to sizes->Array.length - 1 {
      await fixture(session, sizes->Array.getUnsafe(i))
      await exercise(session)
      session->Cost.complete
      await Cost.exec(session, "DELETE FROM deployment")
      await Cost.exec(session, "DELETE FROM binding")
      await Cost.exec(session, "DELETE FROM app")
      await Cost.exec(session, "DELETE FROM release")
      await Cost.exec(session, "DELETE FROM organization")
    }
    await Cost.close(session)
  } catch {
  | e =>
    await Cost.close(session)
    throw(e)
  }
})

test("the allocation budget holds when the whole address range is held", async () => {
  let session = await Cost.open_()
  try {
    await Cost.exec(session, "INSERT INTO organization (id, label) VALUES (1, 'first')")
    await Cost.exec(
      session,
      `WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n
      WHERE v < ${Int.toString(Addresses.count)})
      INSERT INTO binding (id, organization, secret, address)
      SELECT v + 100, 1, '', '10.200.' || (v / 256) || '.' || (v % 256) FROM n`,
    )
    let state = State.ofDatabase(session->Cost.database, ~sealing=Sealing.ofKey(key))
    let binding = await state.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() =>
      4275878552.
    )
    deepEqual(await state.addressed(~binding), None)
    await Cost.close(session)
  } catch {
  | e =>
    await Cost.close(session)
    throw(e)
  }
})
