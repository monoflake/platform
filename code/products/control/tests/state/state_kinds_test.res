/***
 * `State` held to RFC emgxf, a release keeping its kinds and a deployment its kind, and migration
 * 0007 leaving every row before it with none.
 */
open Stored
open Node

test("a release's kinds and a deployment's kind are kept as given, none where none", async () =>
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
    await state.putRelease({
      hash: "aa",
      form: Modules,
      size: 3.,
      kinds: Some([Container, Function]),
    })
    // A second put of one hash changes nothing.
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    await state.putRelease({hash: "bb", form: Image, size: 3., kinds: Some([])})
    await state.putRelease({hash: "cc", form: Modules, size: 3., kinds: None})
    let app = await state.drawApp(~random=scripted(list{16777221.}))
    await state.deploy({app, binding, release: "aa", capacity: 1., kind: Some(Container)})
    let kindsOf = async hash => (await state.release(hash))->Option.map(r => r.kinds)
    deepEqual(
      (
        await kindsOf("aa"),
        await kindsOf("bb"),
        await kindsOf("cc"),
        (await state.deployment(app))->Option.map(d => d.kind),
      ),
      (
        Some(Some([Envelope.Contracts.DeploymentKind.Container, Function])),
        Some(Some([])),
        Some(None),
        Some(Some(Envelope.Contracts.DeploymentKind.Container)),
      ),
      ~message=store.name,
    )
  }
)

test("migration 0007 keeps every release and deployment before it with no kinds", async () => {
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
    "0006-bound.sql",
  ])
  db->Sqlite.exec(
    `INSERT INTO organization (id, label) VALUES (1, 'first');
    INSERT INTO binding (id, organization, secret) VALUES (2, 1, '${Envelope.Hex.encode(secret)}');
    INSERT INTO release (hash, form, size) VALUES ('aa', 'modules', 3);
    INSERT INTO app (id) VALUES (3), (4);
    INSERT INTO deployment (app, binding, release, capacity)
    VALUES (3, 2, 'aa', 1), (4, 2, 'aa', 0);`,
  )
  applied(["0007-kinds.sql", "0008-ingress.sql"])
  let state = State.ofDatabase(Sqlite.asDatabase(db), ~sealing=Sealing.ofKey(key))
  let ran = async app => (await state.deployment(app))->Option.map(d => (d.kind, State.ran(d)))
  deepEqual(
    (
      (await state.release("aa"))->Option.map(r => r.kinds),
      await ran(3.),
      await ran(4.),
      await state.forgetApp(3.),
      await state.forgetApp(4.),
    ),
    (Some(None), Some((None, true)), Some((None, false)), false, true),
  )
})
