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
    let binding = await state.openBinding(~organization=organization.id, ~secret, ~relayed=false)
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
    deepEqual(
      (
        isSealed(await store.kept(~kind="organization", ~id=1.)),
        isSealed(await store.kept(~kind="organization", ~id=2.)),
        isSealed(await store.kept(~kind="binding", ~id=1.)),
      ),
      (true, true, true),
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

test("a control given no key refuses to keep or read a secret, and keeps no binding", async () =>
  for i in 0 to stores->Array.length - 1 {
    let make = stores->Array.getUnsafe(i)
    let store = make()
    let keyless = store.state(Sealing.ofKey(None))
    let refused = (
      await thrown(() => keyless.openOrganization("first", ~secret)),
      await thrown(() => keyless.openBinding(~organization=1., ~secret, ~relayed=false)),
    )
    await store.put(~kind="organization", ~id=5., Envelope.Hex.encode(secret))
    deepEqual(
      (
        refused,
        await thrown(() => keyless.organizationSecret(5.)),
        await keyless.binding(1.),
        await store.kept(~kind="organization", ~id=5.),
      ),
      ((Some(missing), Some(missing)), Some(missing), None, Some(Envelope.Hex.encode(secret))),
      ~message=store.name,
    )
  }
)
