/***
 * `State` drawing the ids of apps, bindings and organizations among every id held, and an app
 * forgotten or retired, in D1 and in objects alike.
 */
open Stored
open Node

test("an app's id drawn is unique among every id held, and drawn again on a conflict", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    // Organizations are counted below the floor, so one above it is written directly.
    await store.put(~kind="organization", ~id=16909060., Envelope.Hex.encode(secret))
    let binding = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    let other = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    ignore(await state.drawApp(~random=() => 169552957.))
    await state.deploy({app: 169552957., binding, release: "aa", capacity: 1., kind: None})
    // An organization's id, a binding's, a deployed app's and 0 are each drawn again.
    let first = await state.drawApp(
      ~random=scripted(list{16909060., other, 169552957., 0., 4275878552.}),
    )
    let second = await state.drawApp(~random=scripted(list{4275878552., 16777223.}))
    let exhausted = await thrown(() => state.drawApp(~random=() => second))
    deepEqual(
      (first, second, exhausted),
      (4275878552., 16777223., Some("every one of 16 app ids drawn is held already")),
      ~message=store.name,
    )
  }
)

test("an app deployed before ids were drawn is held once migrated", async () => {
  let db = Sqlite.openSqlite(":memory:")
  let migrations = fromRoot("code/products/control/migrations")
  let applied = names =>
    names->Array.forEach(name => db->Sqlite.exec(readText(join([migrations, name]))))
  applied(["0001-state.sql", "0002-organizations.sql", "0003-origin.sql"])
  db->Sqlite.exec("INSERT INTO organization (id, label) VALUES (1, 'first');
    INSERT INTO binding (id, organization, secret) VALUES (1, 1, '');
    INSERT INTO release (hash, form, size) VALUES ('aa', 'modules', 3);
    INSERT INTO deployment (app, binding, release, capacity) VALUES (2, 1, 'aa', 1);")
  applied(["0004-app.sql"])
  deepEqual(
    (
      await Sqlite.asDatabase(db)
      ->Stores.prepare("SELECT id FROM app")
      ->Stores.bind([])
      ->Stores.first
    )
    ->Nullable.toOption
    ->Option.map((row: {"id": float}) => row["id"]),
    Some(2.),
  )
})

test("an organization's next id is counted on past every id an app or a binding holds", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let first = await state.openOrganization("first", ~secret)
    // Held below the floor as kept before ids were drawn, since no draw gives them.
    await store.put(~kind="binding", ~id=2., Envelope.Hex.encode(secret))
    await store.app(3.)
    await store.app(4.)
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    await state.deploy({app: 4., binding: 2., release: "aa", capacity: 1., kind: None})
    let second = await state.openOrganization("second", ~secret)
    deepEqual(
      (
        (await state.binding(2.))->Option.map(b => b.organization),
        (await state.deployment(4.))->Option.map(d => d.capacity),
        second.id,
      ),
      (Some(first.id), Some(1.), 5.),
      ~message=store.name,
    )
  }
)

test("an organization opened after ids drawn above the floor is given the next low one", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let first = await state.openOrganization("first", ~secret)
    let binding = await state.openBinding(
      ~organization=first.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    let app = await state.drawApp(~random=Memory.counting())
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    await state.deploy({app, binding, release: "aa", capacity: 1., kind: None})
    let second = await state.openOrganization("second", ~secret)
    deepEqual((binding, app, second.id), (16777216., 16777217., 2.), ~message=store.name)
  }
)

test(
  "a binding's id drawn is unique among every id held, and drawn again on a conflict",
  async () =>
    for i in 0 to stores->Array.length - 1 {
      let make = stores->Array.getUnsafe(i)
      let store = make()
      let state = store.state(Sealing.ofKey(key))
      let organization = await state.openOrganization("first", ~secret)
      // Organizations are counted below the floor, so one above it is written directly.
      await store.put(~kind="organization", ~id=16909060., Envelope.Hex.encode(secret))
      let open_ = random =>
        state.openBinding(~organization=organization.id, ~secret, ~relayed=false, ~random)
      // An organization's id and 0 are each drawn again.
      let first = await open_(scripted(list{16909060., 0., 169552957.}))
      let app = await state.drawApp(~random=scripted(list{first, 16777223.}))
      await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
      ignore(await state.drawApp(~random=() => 16777225.))
      await state.deploy({app: 16777225., binding: first, release: "aa", capacity: 1., kind: None})
      // A binding's, an app's and a deployed app's are each drawn again.
      let second = await open_(scripted(list{first, app, 16777225., 4275878552.}))
      let asked = ref(0)
      let exhausted = await thrown(() =>
        open_(
          () => {
            asked := asked.contents + 1
            first
          },
        )
      )
      deepEqual(
        (first, app, second, exhausted, asked.contents),
        (
          169552957.,
          16777223.,
          4275878552.,
          Some("every one of 16 binding ids drawn is held already"),
          16,
        ),
        ~message=store.name,
      )
    },
)

test("an app drawn and never run is forgotten, one that ran or none held is not", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let binding = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=scripted(list{16777218.}),
    )
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    let never = await state.drawApp(~random=scripted(list{16777221.}))
    await state.deploy({app: never, binding, release: "aa", capacity: 0., kind: None})
    let ran = await state.drawApp(~random=scripted(list{16777222.}))
    await state.deploy({app: ran, binding, release: "aa", capacity: 1., kind: None})
    let bare = await state.drawApp(~random=scripted(list{16777223.}))
    // A function deployed into no container ran though its capacity is 0, emgxf.
    let uncontained = await state.drawApp(~random=scripted(list{16777224.}))
    await state.deploy({
      app: uncontained,
      binding,
      release: "aa",
      capacity: 0.,
      kind: Some(Function),
    })
    deepEqual(
      (
        await state.forgetApp(never),
        await state.forgetApp(ran),
        await state.forgetApp(bare),
        await state.forgetApp(99.),
        await state.forgetApp(never),
        await state.forgetApp(uncontained),
        await state.deployment(never),
        (await state.deployment(ran))->Option.map(d => d.capacity),
        (await state.deployment(uncontained))->Option.map(d => (d.capacity, d.kind)),
        // A forgotten id is free to be drawn again.
        await state.drawApp(~random=scripted(list{16777221.})),
      ),
      (
        true,
        false,
        true,
        false,
        false,
        false,
        None,
        Some(1.),
        Some((0., Some(Envelope.Contracts.DeploymentKind.Function))),
        16777221.,
      ),
      ~message=store.name,
    )
  }
)

test("a forgotten app's deploy lands nowhere, and a halfway forget is finished alike", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let binding = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=scripted(list{16777218.}),
    )
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    let app = await state.drawApp(~random=scripted(list{16777221.}))
    await state.deploy({app, binding, release: "aa", capacity: 0., kind: None})
    let forgotten = await state.forgetApp(app)
    // The deploy's container is declared after the forget, as a deploy racing it would.
    await state.deploy({app, binding, release: "aa", capacity: 1., kind: None})
    let landed = await state.deployment(app)
    await store.orphan(~app=16777223., ~binding)
    let orphaned = (await state.forgetApp(16777223.), await state.deployment(16777223.))
    deepEqual((forgotten, landed, orphaned), (true, None, (true, None)), ~message=store.name)
  }
)

test(
  "an app that ran is retired whatever it holds, one numbered before ids were drawn too",
  async () =>
    for i in 0 to stores->Array.length - 1 {
      let make = stores->Array.getUnsafe(i)
      let store = make()
      let state = store.state(Sealing.ofKey(key))
      let organization = await state.openOrganization("first", ~secret)
      let binding = await state.openBinding(
        ~organization=organization.id,
        ~secret,
        ~relayed=false,
        ~random=scripted(list{16777218.}),
      )
      await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
      let ran = await state.drawApp(~random=scripted(list{16777221.}))
      await state.deploy({app: ran, binding, release: "aa", capacity: 1., kind: None})
      await store.numbered(~app=1., ~binding)
      let before = (await state.hasApp(ran), await state.hasApp(1.), await state.hasApp(99.))
      await state.retireApp(ran)
      await state.retireApp(1.)
      // Nothing held is no failure.
      await state.retireApp(99.)
      // A deploy declared after the removal lands nowhere.
      await state.deploy({app: ran, binding, release: "aa", capacity: 1., kind: None})
      deepEqual(
        (
          before,
          await state.hasApp(ran),
          await state.deployment(ran),
          await state.deployment(1.),
          await state.drawApp(~random=scripted(list{16777221.})),
        ),
        ((true, false, false), false, None, None, 16777221.),
        ~message=store.name,
      )
    },
)
