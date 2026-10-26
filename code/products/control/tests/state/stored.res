/*** The stores each state keeps, D1 and objects, read and written beneath it by its tests. */

let key = Some(Envelope.Base64url.encode(Web.random(32)))
let secret = Uint8Array.fromArray(Array.fromInitializer(~length=32, i => i))

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
  /** An app's record written directly, as a migration or an older control kept it. */
  app: float => promise<unit>,
  /** A deployment of no container on a binding, with no app record, as a forget halfway leaves. */
  orphan: (~app: float, ~binding: float) => promise<unit>,
  /** A deployment of a container with no app record, as one kept before ids were drawn. */
  numbered: (~app: float, ~binding: float) => promise<unit>,
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
    app: id => statement("INSERT INTO app (id) VALUES (?)", [Number(id)])->Stores.run,
    orphan: (~app, ~binding) =>
      statement(
        "INSERT INTO deployment (app, binding, release, capacity) VALUES (?, ?, 'aa', 0)",
        [Number(app), Number(binding)],
      )->Stores.run,
    numbered: (~app, ~binding) =>
      statement(
        "INSERT INTO deployment (app, binding, release, capacity) VALUES (?, ?, 'aa', 1)",
        [Number(app), Number(binding)],
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
    app: async id =>
      held->Dict.set(
        `state/apps/${Float.toString(id)}`,
        Web.utf8(JSON.stringify(Object(dict{"id": Number(id)}))),
      ),
    orphan: async (~app, ~binding) =>
      held->Dict.set(
        `state/deployments/${Float.toString(app)}`,
        Web.utf8(
          JSON.stringify(
            Object(
              dict{
                "app": Number(app),
                "binding": Number(binding),
                "release": String("aa"),
                "capacity": Number(0.),
              },
            ),
          ),
        ),
      ),
    numbered: async (~app, ~binding) =>
      held->Dict.set(
        `state/deployments/${Float.toString(app)}`,
        Web.utf8(
          JSON.stringify(
            Object(
              dict{
                "app": Number(app),
                "binding": Number(binding),
                "release": String("aa"),
                "capacity": Number(1.),
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
