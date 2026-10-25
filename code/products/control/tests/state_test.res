/***
 * `State` held to RFC fhg6w, each secret sealed for its record in D1 and in objects alike, a plain
 * one written back sealed, and a control with no key refused.
 */
open Node

let key = Some(Envelope.Base64url.encode(Web.random(32)))
let secret = Uint8Array.fromArray(Array.fromInitializer(~length=32, i => i))
let other = Uint8Array.fromArray(Array.make(~length=32, 9))
let missing = "the control is given no SEALING_KEY, so it keeps and reads no secret"

/** A store as each state keeps it, read and written beneath the state. */
type store = {
  name: string,
  state: Sealing.t => State.t,
  /** A record written as an older control kept it, its secret as given. */
  put: (~kind: string, ~id: float, string) => promise<unit>,
  kept: (~kind: string, ~id: float) => promise<option<string>>,
  /** A record kept again whole under another id, as a copy beneath the state would. */
  copy: (~kind: string, ~from: float, ~into: float) => promise<unit>,
  /** Whether a plain binding's secret is written back sealed as read, or at its next write. */
  writesBack: bool,
  /** A deployment of no container on binding 2, with no app record, as a forget halfway leaves. */
  orphan: float => promise<unit>,
}

type secretRow = {secret: Nullable.t<string>}

let d1 = () => {
  let database = Sqlite.database()
  let statement = (sql, values) => database->Stores.prepare(sql)->Stores.bind(values)
  {
    name: "D1",
    state: sealing => State.ofDatabase(database, ~sealing),
    put: (~kind, ~id, text) =>
      kind == "organization"
        ? statement(
            "INSERT INTO organization (id, label, secret) VALUES (?, ?, ?)",
            [Number(id), Text(`label-${Float.toString(id)}`), Text(text)],
          )->Stores.run
        : statement(
            "INSERT INTO binding (id, organization, secret) VALUES (?, 1, ?)",
            [Number(id), Text(text)],
          )->Stores.run,
    kept: async (~kind, ~id) =>
      (await statement(`SELECT secret FROM ${kind} WHERE id = ?`, [Number(id)])->Stores.first)
      ->Nullable.toOption
      ->Option.flatMap((row: secretRow) => row.secret->Nullable.toOption),
    copy: (~kind, ~from, ~into) =>
      kind == "organization"
        ? statement(
            "INSERT INTO organization (id, label, secret)
            SELECT ?, label || '-copy', secret FROM organization WHERE id = ?",
            [Number(into), Number(from)],
          )->Stores.run
        : statement(
            "INSERT INTO binding (id, organization, secret, relayed)
            SELECT ?, organization, secret, relayed FROM binding WHERE id = ?",
            [Number(into), Number(from)],
          )->Stores.run,
    writesBack: true,
    orphan: app =>
      statement(
        "INSERT INTO deployment (app, binding, release, capacity) VALUES (?, 2, 'aa', 0)",
        [Number(app)],
      )->Stores.run,
  }
}

let objects = () => {
  let held: dict<Uint8Array.t> = dict{}
  let kept: Objects.t = {
    write: async (name, bytes) => Ok(held->Dict.set(name, bytes)),
    read: async name => Ok(held->Dict.get(name)),
    list: async prefix => Ok(
      held
      ->Dict.keysToArray
      ->Array.filter(n => n->String.startsWith(prefix))
      ->Array.toSorted(String.compare),
    ),
    delete: async name => Ok(held->Dict.delete(name)),
  }
  let at = (kind, id) => `state/${kind}s/${Float.toString(id)}`
  {
    name: "objects",
    state: sealing => State.ofObjects(kept, ~sealing),
    put: async (~kind, ~id, text) => {
      let record = dict{"id": JSON.Number(id), "secret": String(text)}
      if kind == "organization" {
        record->Dict.set("label", String(`label-${Float.toString(id)}`))
      } else {
        record->Dict.set("organization", Number(1.))
        record->Dict.set("relayed", Boolean(false))
      }
      held->Dict.set(at(kind, id), Web.utf8(JSON.stringify(Object(record))))
    },
    kept: async (~kind, ~id) =>
      held
      ->Dict.get(at(kind, id))
      ->Option.flatMap(bytes =>
        JSON.parseOrThrow(Web.fromUtf8(bytes))
        ->JSON.Decode.object
        ->Option.flatMap(o => o->Dict.get("secret"))
        ->Option.flatMap(JSON.Decode.string)
      ),
    copy: async (~kind, ~from, ~into) =>
      held
      ->Dict.get(at(kind, from))
      ->Option.forEach(bytes => held->Dict.set(at(kind, into), bytes)),
    writesBack: false,
    orphan: async app =>
      held->Dict.set(
        `state/deployments/${Float.toString(app)}`,
        Web.utf8(
          JSON.stringify(
            Object(
              dict{
                "app": Number(app),
                "binding": Number(2.),
                "release": String("aa"),
                "capacity": Number(0.),
              },
            ),
          ),
        ),
      ),
  }
}

let stores = [d1, objects]

let thrown = async f =>
  switch await f() {
  | _ => None
  | exception JsExn(e) => e->JsExn.message
  }

/** Whether a secret is kept sealed, its version first and never its plain hex. */
let isSealed = kept =>
  switch kept {
  | Some(text) => text->String.startsWith("01") && text->String.length == 2 * (1 + 12 + 32 + 16)
  | None => false
  }

test("a secret is kept sealed for its record, and opens as it was given", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let again = await state.openOrganization("first", ~secret=other)
    let binding = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    deepEqual(
      (
        isSealed(await store.kept(~kind="organization", ~id=organization.id)),
        isSealed(await store.kept(~kind="binding", ~id=binding)),
        again.secret,
        await state.organizationSecret(organization.id),
        (await state.binding(binding))->Option.map(b => b.secret),
      ),
      (true, true, secret, Some(secret), Some(secret)),
      ~message=store.name,
    )
  }
)

test("a plain secret is read as it is and written back sealed", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let plain = Envelope.Hex.encode(secret)
    await store.put(~kind="organization", ~id=1., plain)
    await store.put(~kind="organization", ~id=2., plain)
    await store.put(~kind="binding", ~id=1., plain)
    let state = store.state(Sealing.ofKey(key))
    let read = (
      await state.organizationSecret(1.),
      (await state.openOrganization("label-2", ~secret=other)).secret,
      (await state.binding(1.))->Option.map(b => b.secret),
    )
    deepEqual(read, (Some(secret), secret, Some(secret)), ~message=store.name)
    // In objects a binding's write back raced another request's write of it, so none is made.
    deepEqual(
      (
        isSealed(await store.kept(~kind="organization", ~id=1.)),
        isSealed(await store.kept(~kind="organization", ~id=2.)),
        (await store.kept(~kind="binding", ~id=1.)) == Some(plain),
      ),
      (true, true, !store.writesBack),
      ~message=store.name,
    )
    // The binding's next write seals it, keeping what that write changed.
    ignore(await state.addressed(~binding=1., ~address="10.200.0.1"))
    deepEqual(
      (
        isSealed(await store.kept(~kind="binding", ~id=1.)),
        (await state.binding(1.))->Option.map(b => (b.secret, b.address)),
      ),
      (true, Some((secret, Some("10.200.0.1")))),
      ~message=store.name,
    )
    // Read again, the seals written back open as the plain secrets did.
    deepEqual(
      (
        await state.organizationSecret(1.),
        (await state.openOrganization("label-2", ~secret=other)).secret,
        (await state.binding(1.))->Option.map(b => b.secret),
      ),
      read,
      ~message=store.name,
    )
  }
)

test("a seal moved to another record, or an empty secret, is a fault", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("label-1", ~secret)
    let moved = await store.kept(~kind="organization", ~id=organization.id)
    await store.put(~kind="organization", ~id=2., moved->Option.getOr(""))
    await store.put(~kind="binding", ~id=1., "")
    deepEqual(
      (await thrown(() => state.organizationSecret(2.)), await thrown(() => state.binding(1.))),
      (
        Some("the secret kept at organization:2:secret does not open under this key"),
        Some("the binding 1 holds an empty secret"),
      ),
      ~message=store.name,
    )
  }
)

test("a whole record copied to another id does not open there", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("label-1", ~secret)
    let binding = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    ignore(await state.addressed(~binding, ~address="10.200.0.1"))
    await state.routed(~binding)
    await store.copy(~kind="organization", ~from=organization.id, ~into=2.)
    await store.copy(~kind="binding", ~from=binding, ~into=9.)
    // Objects once opened a copied document under its own id field, so the copy opened.
    let moved = store.writesBack
      ? (
          Some("the secret kept at organization:2:secret does not open under this key"),
          Some("the secret kept at binding:9:secret does not open under this key"),
        )
      : (
          Some("the record at state/organizations/2 holds another id than its path's"),
          Some("the record at state/bindings/9 holds another id than its path's"),
        )
    deepEqual(
      (await thrown(() => state.organizationSecret(2.)), await thrown(() => state.binding(9.))),
      moved,
      ~message=store.name,
    )
  }
)

test("a stale copy beside the records, named by more than an id, is no record", async () => {
  let held: dict<Uint8Array.t> = dict{}
  let kept: Objects.t = {
    write: async (name, bytes) => Ok(held->Dict.set(name, bytes)),
    read: async name => Ok(held->Dict.get(name)),
    list: async prefix => Ok(
      held->Dict.keysToArray->Array.filter(n => n->String.startsWith(prefix)),
    ),
    delete: async name => Ok(held->Dict.delete(name)),
  }
  let state = State.ofObjects(kept, ~sealing=Sealing.ofKey(key))
  let organization = await state.openOrganization("label-1", ~secret)
  let binding = await state.openBinding(
    ~organization=organization.id,
    ~secret,
    ~relayed=false,
    ~random=Memory.counting(),
  )
  ignore(await state.addressed(~binding, ~address="10.200.0.1"))
  await state.routed(~binding)
  let at = `state/bindings/${Float.toString(binding)}`
  held->Dict.set(`${at}-old`, held->Dict.getUnsafe(at))
  // parseFloat once read `2-old` as id 2, so a stale copy could answer for binding 2.
  deepEqual(
    await thrown(() => state.addressedAt("10.200.0.1")),
    Some(`the record at ${at}-old is named by no id`),
  )
})

test("a control given no key refuses to keep or read a secret, and writes nothing", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let keyless = store.state(Sealing.ofKey(None))
    let refused = (
      await thrown(() => keyless.openOrganization("first", ~secret)),
      await thrown(() =>
        keyless.openBinding(~organization=1., ~secret, ~relayed=false, ~random=Memory.counting())
      ),
    )
    // A keyless D1 control once inserted the organization before its seal threw.
    let opened = await keyless.hasOrganization(1.)
    await store.put(~kind="organization", ~id=5., Envelope.Hex.encode(secret))
    deepEqual(
      (
        refused,
        opened,
        await thrown(() => keyless.organizationSecret(5.)),
        await keyless.binding(1.),
        await store.kept(~kind="organization", ~id=5.),
      ),
      (
        (Some(missing), Some(missing)),
        false,
        Some(missing),
        None,
        Some(Envelope.Hex.encode(secret)),
      ),
      ~message=store.name,
    )
  }
)

test("a secret not 32 bytes is refused before any write", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let short = Uint8Array.fromArray([1, 2, 3])
    deepEqual(
      (
        await thrown(() => state.openOrganization("first", ~secret=short)),
        await thrown(() =>
          state.openBinding(
            ~organization=1.,
            ~secret=short,
            ~relayed=false,
            ~random=Memory.counting(),
          )
        ),
        await state.hasOrganization(1.),
        await state.binding(1.),
      ),
      (
        Some("the secret to seal at organization:0:secret is not 32 bytes"),
        Some("the secret to seal at binding:0:secret is not 32 bytes"),
        false,
        None,
      ),
      ~message=store.name,
    )
  }
)

type countRow = {count: float}

test("a binding whose secret is not written after its insert is deleted", async () => {
  let database = Sqlite.database()
  let state = State.ofDatabase(
    Sqlite.refusing(database, "UPDATE binding SET secret"),
    ~sealing=Sealing.ofKey(key),
  )
  let {id: organization} = await state.openOrganization("first", ~secret)
  let refused = await thrown(() =>
    state.openBinding(~organization, ~secret, ~relayed=false, ~random=Memory.counting())
  )
  let count =
    (
      await database
      ->Stores.prepare("SELECT COUNT(*) AS count FROM binding")
      ->Stores.bind([])
      ->Stores.first
    )
    ->Nullable.toOption
    ->Option.map((row: countRow) => row.count)
  // The row was deleted where its seal threw, and kept with an empty secret where the update did.
  deepEqual((refused, count), (Some("refused UPDATE binding SET secret"), Some(0.)))
})

test("a binding's origin is written once, and never over another reach", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let state = make().state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let first = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    let second = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    let origin = async id => (await state.binding(id))->Option.flatMap(b => b.origin)
    let fresh = await origin(first)
    let written = await state.originated(~binding=first, ~origin="https://driver.example.com")
    let again = await state.originated(~binding=first, ~origin="https://other.example.com")
    ignore(await state.addressed(~binding=second, ~address="10.200.0.2"))
    await state.routed(~binding=second)
    let tunneled = await state.originated(~binding=second, ~origin="https://driver.example.com")
    deepEqual(
      (fresh, written, again, await origin(first), tunneled, await origin(second)),
      (None, true, false, Some("https://driver.example.com"), false, None),
      ~message=make().name,
    )
  }
)

test("storage is never a binding reached by its origin", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let state = make().state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let first = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    let second = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=Memory.counting(),
    )
    ignore(await state.originated(~binding=first, ~origin="https://driver.example.com"))
    // A tunnel bind racing the origin's is given no address, whether one is given or taken.
    let refused = (
      await state.addressed(~binding=first, ~address="10.200.0.1"),
      await state.addressed(~binding=first),
      (await state.binding(first))->Option.flatMap(b => b.address),
    )
    deepEqual(refused, (None, None, None), ~message=make().name)
    let none = await state.storage(organization.id)
    ignore(await state.addressed(~binding=second, ~address="10.200.0.2"))
    await state.routed(~binding=second)
    deepEqual(
      (none, (await state.storage(organization.id))->Option.map(b => b.id)),
      (None, Some(second)),
      ~message=make().name,
    )
  }
)

/** Draws given in turn, each asked of `random`. */
let scripted = draws => {
  let left = ref(draws)
  () =>
    switch left.contents {
    | list{next, ...rest} =>
      left := rest
      next
    | list{} => JsError.throwWithMessage("no draw left")
    }
}

test("an app's id drawn is unique among every id held, and drawn again on a conflict", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
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
    await state.putRelease({hash: "aa", form: Modules, size: 3.})
    ignore(await state.drawApp(~random=() => 169552957.))
    await state.deploy({app: 169552957., binding, release: "aa", capacity: 1.})
    // The organization's id, a binding's, a deployed app's and 0 are each drawn again.
    let first = await state.drawApp(
      ~random=scripted(list{organization.id, other, 169552957., 0., 4275878552.}),
    )
    let second = await state.drawApp(~random=scripted(list{4275878552., 7.}))
    let exhausted = await thrown(() => state.drawApp(~random=() => 7.))
    deepEqual(
      (first, second, exhausted),
      (4275878552., 7., Some("every one of 16 app ids drawn is held already")),
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
    let binding = await state.openBinding(
      ~organization=first.id,
      ~secret,
      ~relayed=false,
      ~random=scripted(list{2.}),
    )
    let app = await state.drawApp(~random=scripted(list{3.}))
    await state.putRelease({hash: "aa", form: Modules, size: 3.})
    ignore(await state.drawApp(~random=() => 4.))
    await state.deploy({app: 4., binding, release: "aa", capacity: 1.})
    let second = await state.openOrganization("second", ~secret)
    deepEqual((binding, app, second.id), (2., 3., 5.), ~message=store.name)
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
      let open_ = random =>
        state.openBinding(~organization=organization.id, ~secret, ~relayed=false, ~random)
      // The organization's id and 0 are each drawn again.
      let first = await open_(scripted(list{organization.id, 0., 169552957.}))
      let app = await state.drawApp(~random=scripted(list{first, 7.}))
      await state.putRelease({hash: "aa", form: Modules, size: 3.})
      ignore(await state.drawApp(~random=() => 9.))
      await state.deploy({app: 9., binding: first, release: "aa", capacity: 1.})
      // A binding's, an app's and a deployed app's are each drawn again.
      let second = await open_(scripted(list{first, app, 9., 4275878552.}))
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
          7.,
          4275878552.,
          Some("every one of 16 binding ids drawn is held already"),
          16,
        ),
        ~message=store.name,
      )
    },
)

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
    let (a, b, c) = (await open_(2.), await open_(3.), await open_(4.))
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
      ~random=scripted(list{2.}),
    )
    await state.putRelease({hash: "aa", form: Modules, size: 3.})
    let never = await state.drawApp(~random=scripted(list{5.}))
    await state.deploy({app: never, binding, release: "aa", capacity: 0.})
    let ran = await state.drawApp(~random=scripted(list{6.}))
    await state.deploy({app: ran, binding, release: "aa", capacity: 1.})
    let bare = await state.drawApp(~random=scripted(list{7.}))
    deepEqual(
      (
        await state.forgetApp(never),
        await state.forgetApp(ran),
        await state.forgetApp(bare),
        await state.forgetApp(99.),
        await state.forgetApp(never),
        await state.deployment(never),
        (await state.deployment(ran))->Option.map(d => d.capacity),
        // A forgotten id is free to be drawn again.
        await state.drawApp(~random=scripted(list{5.})),
      ),
      (true, false, true, false, false, None, Some(1.), 5.),
      ~message=store.name,
    )
  }
)

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
      let unrouted = await open_(3.)
      ignore(await state.addressed(~binding=unrouted))
      let high = await open_(4275878552.)
      ignore(await state.addressed(~binding=high))
      let none = await state.storage(organization.id)
      await state.routed(~binding=high)
      let low = await open_(2.)
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
  let low = await state.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() => 9.)
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
      ~random=scripted(list{2.}),
    )
    await state.putRelease({hash: "aa", form: Modules, size: 3.})
    let app = await state.drawApp(~random=scripted(list{5.}))
    await state.deploy({app, binding, release: "aa", capacity: 0.})
    let forgotten = await state.forgetApp(app)
    // The deploy's container is declared after the forget, as a deploy racing it would.
    await state.deploy({app, binding, release: "aa", capacity: 1.})
    let landed = await state.deployment(app)
    await store.orphan(7.)
    let orphaned = (await state.forgetApp(7.), await state.deployment(7.))
    deepEqual((forgotten, landed, orphaned), (true, None, (true, None)), ~message=store.name)
  }
)

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
    let later = await state.openBinding(~organization=1., ~secret, ~relayed=false, ~random=() => 7.)
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
