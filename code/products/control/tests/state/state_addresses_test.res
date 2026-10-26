/***
 * `State` giving a binding its address and its order once bound, storage the first bound, and
 * the bindings kept before either was.
 */
open Stored
open Node

test("a binding's address is the one given, else the lowest free, and once held kept", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let open_ = id =>
      state.openBinding(
        ~organization=organization.id,
        ~secret,
        ~relayed=false,
        ~random=scripted(list{id}),
      )
    let (a, b, c) = (await open_(16777218.), await open_(16777219.), await open_(16777220.))
    deepEqual(
      (
        await state.addressed(~binding=a, ~address="10.200.0.7"),
        await state.addressed(~binding=b),
        await state.addressed(~binding=b),
        await state.addressed(~binding=b, ~address="10.200.0.9"),
        await state.addressed(~binding=c),
        await state.addressed(~binding=99.),
        (await state.binding(c))->Option.flatMap(b => b.address),
      ),
      (
        Some("10.200.0.7"),
        Some("10.200.0.1"),
        Some("10.200.0.1"),
        Some("10.200.0.1"),
        Some("10.200.0.2"),
        None,
        Some("10.200.0.2"),
      ),
      ~message=store.name,
    )
  }
)

test("a binding is given no address once every one of the range is held", async () => {
  let database = Sqlite.database()
  let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
  await run("INSERT INTO organization (id, label) VALUES (1, 'first')")
  await run(
    `WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n WHERE v < ${Int.toString(
        Addresses.count,
      )})
    INSERT INTO binding (id, organization, secret, address)
    SELECT v + 100, 1, '', '10.200.' || (v / 256) || '.' || (v % 256) FROM n`,
  )
  let state = State.ofDatabase(database, ~sealing=Sealing.ofKey(key))
  let binding = await state.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() =>
    4275878552.
  )
  deepEqual(await state.addressed(~binding), None)
})

test("a binding whose tunnel was made before its address was kept is given its id's", async () => {
  let db = Sqlite.openSqlite(":memory:")
  let migrations = fromRoot("code/products/control/migrations")
  let applied = names =>
    names->Array.forEach(name => db->Sqlite.exec(readText(join([migrations, name]))))
  applied(["0001-state.sql", "0002-organizations.sql", "0003-origin.sql", "0004-app.sql"])
  db->Sqlite.exec("INSERT INTO organization (id, label) VALUES (1, 'first');
    INSERT INTO binding (id, organization, secret, tunnel) VALUES (2, 1, '', 't-2');
    INSERT INTO binding (id, organization, secret, tunnel, address)
    VALUES (3, 1, '', 't-3', '10.200.0.3');
    INSERT INTO binding (id, organization, secret, origin)
    VALUES (4, 1, '', 'https://driver.example.com');
    INSERT INTO binding (id, organization, secret) VALUES (5, 1, '');
    INSERT INTO binding (id, organization, secret, tunnel) VALUES (300, 1, '', 't-300');")
  applied(["0005-address.sql"])
  let database = Sqlite.asDatabase(db)
  let addressOf = async id =>
    (
      await database
      ->Stores.prepare("SELECT address FROM binding WHERE id = ?")
      ->Stores.bind([Number(id)])
      ->Stores.first
    )
    ->Nullable.toOption
    ->Option.flatMap((row: {"address": Nullable.t<string>}) => row["address"]->Nullable.toOption)
  deepEqual(
    (
      await addressOf(2.),
      await addressOf(3.),
      await addressOf(4.),
      await addressOf(5.),
      await addressOf(300.),
    ),
    (Some("10.200.0.2"), Some("10.200.0.3"), None, None, Some("10.200.1.44")),
  )
})

test(
  "storage is the binding first bound by its route, though a later one is drawn below it",
  async () =>
    for i in 0 to stores->Array.length - 1 {
      let make = stores->Array.getUnsafe(i)
      let state = make().state(Sealing.ofKey(key))
      let organization = await state.openOrganization("first", ~secret)
      let open_ = id =>
        state.openBinding(
          ~organization=organization.id,
          ~secret,
          ~relayed=false,
          ~random=scripted(list{id}),
        )
      // Addressed first and never routed, a binding is no storage and is never bound.
      let unrouted = await open_(16777219.)
      ignore(await state.addressed(~binding=unrouted))
      let high = await open_(4275878552.)
      ignore(await state.addressed(~binding=high))
      let none = await state.storage(organization.id)
      await state.routed(~binding=high)
      let low = await open_(16777218.)
      ignore(await state.addressed(~binding=low))
      await state.routed(~binding=low)
      // A bound binding's address is never given back.
      await state.unaddressed(~binding=high, ~address="10.200.0.2")
      let bound = async id => (await state.binding(id))->Option.flatMap(b => b.bound)
      deepEqual(
        (
          none,
          (await state.storage(organization.id))->Option.map(b => b.id),
          (await state.binding(high))->Option.flatMap(b => b.address),
          await bound(unrouted),
          (await bound(high))->Option.isSome && (await bound(high)) < (await bound(low)),
        ),
        (None, Some(high), Some("10.200.0.2"), None, true),
        ~message=make().name,
      )
    },
)

test("bindings given an address before keep the order their ids gave them", async () => {
  let database = Sqlite.database()
  let run = sql => database->Stores.prepare(sql)->Stores.bind([])->Stores.run
  await run("INSERT INTO organization (id, label) VALUES (1, 'first')")
  // Kept as the migration leaves rows addressed before it, their order their ids.
  await run(
    `INSERT INTO binding (id, organization, secret, address, bound) VALUES
    (3, 1, '${Envelope.Hex.encode(secret)}', '10.200.0.3', 3),
    (2, 1, '${Envelope.Hex.encode(secret)}', '10.200.0.2', 2)`,
  )
  let state = State.ofDatabase(database, ~sealing=Sealing.ofKey(key))
  let low = await state.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() =>
    16777225.
  )
  ignore(await state.addressed(~binding=low))
  await state.routed(~binding=low)
  deepEqual(
    (
      (await state.storage(1.))->Option.map(b => b.id),
      (await state.binding(low))->Option.flatMap(b => b.address),
    ),
    (Some(2.), Some("10.200.0.1")),
  )
})

test("migration 0006 orders the bindings addressed before it by their ids", async () => {
  let db = Sqlite.openSqlite(":memory:")
  let migrations = fromRoot("code/products/control/migrations")
  let applied = names =>
    names->Array.forEach(name => db->Sqlite.exec(readText(join([migrations, name]))))
  applied([
    "0001-state.sql",
    "0002-organizations.sql",
    "0003-origin.sql",
    "0004-app.sql",
    "0005-address.sql",
  ])
  db->Sqlite.exec("INSERT INTO organization (id, label) VALUES (1, 'first');
    INSERT INTO binding (id, organization, secret, address) VALUES (1, 1, '', '10.200.0.1');
    INSERT INTO binding (id, organization, secret) VALUES (2, 1, '');")
  applied(["0006-bound.sql"])
  let boundOf = async id =>
    (
      await Sqlite.asDatabase(db)
      ->Stores.prepare("SELECT bound FROM binding WHERE id = ?")
      ->Stores.bind([Number(id)])
      ->Stores.first
    )
    ->Nullable.toOption
    ->Option.flatMap((row: {"bound": Nullable.t<float>}) => row["bound"]->Nullable.toOption)
  deepEqual((await boundOf(1.), await boundOf(2.)), (Some(1.), None))
})

test(
  "a binding kept over objects before the order was, an address and a tunnel, stays bound",
  async () => {
    let held: dict<Uint8Array.t> = dict{}
    let kept: Objects.t = {
      write: async (name, bytes) => Ok(held->Dict.set(name, bytes)),
      read: async name => Ok(held->Dict.get(name)),
      list: async prefix => Ok(
        held->Dict.keysToArray->Array.filter(n => n->String.startsWith(prefix)),
      ),
      delete: async name => Ok(held->Dict.delete(name)),
    }
    let record = (name, json) => held->Dict.set(name, Web.utf8(json))
    let plain = Envelope.Hex.encode(secret)
    record("state/organizations/1", `{"id": 1, "label": "first", "secret": "${plain}"}`)
    // Exactly as the control kept it before this wave, with no field for the order.
    record(
      "state/bindings/2",
      `{"id": 2, "organization": 1, "secret": "${plain}", "relayed": false, "tunnel": "t-2", "address": "10.200.0.2"}`,
    )
    let state = State.ofObjects(kept, ~sealing=Sealing.ofKey(key))
    let later = await state.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() =>
      16777223.
    )
    ignore(await state.addressed(~binding=later))
    await state.routed(~binding=later)
    deepEqual(
      (
        (await state.binding(2.))->Option.map(b => (b.address, b.bound)),
        (await state.storage(1.))->Option.map(b => b.id),
        (await state.binding(later))->Option.map(b => (b.address, b.bound)),
      ),
      (Some((Some("10.200.0.2"), Some(2.))), Some(2.), Some((Some("10.200.0.1"), Some(3.)))),
    )
  },
)
