/***
 * `State` held to RFC fhg6w, each secret sealed for its record in D1 and in objects alike, a plain
 * one written back sealed, and a control with no key refused.
 */
open Stored
open Node

let other = Uint8Array.fromArray(Array.make(~length=32, 9))
let missing = "the control is given no SEALING_KEY, so it keeps and reads no secret"

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
