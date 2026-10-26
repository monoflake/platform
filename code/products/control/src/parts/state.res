module DeploymentForm = Envelope.Contracts.DeploymentForm
module DeploymentKind = Envelope.Contracts.DeploymentKind

type binding = {
  id: float,
  organization: float,
  secret: Uint8Array.t,
  tunnel: option<string>,
  address: option<string>,
  origin: option<string>,
  relayed: bool,
  bound: option<float>,
}

type organization = {id: float, secret: Uint8Array.t}

type release = {
  hash: string,
  form: DeploymentForm.t,
  size: float,
  kinds: option<array<DeploymentKind.t>>,
}

type deployment = {
  app: float,
  binding: float,
  release: string,
  capacity: float,
  kind: option<DeploymentKind.t>,
}

let ran = (d: deployment) => d.kind->Option.isSome || d.capacity != 0.

type t = {
  openOrganization: (string, ~secret: Uint8Array.t) => promise<organization>,
  hasOrganization: float => promise<bool>,
  organizationSecret: float => promise<option<Uint8Array.t>>,
  openBinding: (
    ~organization: float,
    ~secret: Uint8Array.t,
    ~relayed: bool,
    ~random: unit => float,
  ) => promise<float>,
  binding: float => promise<option<binding>>,
  storage: float => promise<option<binding>>,
  addressedAt: string => promise<option<binding>>,
  tunneled: (~binding: float, ~tunnel: string) => promise<unit>,
  addressed: (~binding: float, ~address: string=?) => promise<option<string>>,
  unaddressed: (~binding: float, ~address: string) => promise<unit>,
  routed: (~binding: float) => promise<unit>,
  originated: (~binding: float, ~origin: string) => promise<bool>,
  putRelease: release => promise<unit>,
  release: string => promise<option<release>>,
  drawApp: (~random: unit => float) => promise<float>,
  forgetApp: float => promise<bool>,
  hasApp: float => promise<bool>,
  retireApp: float => promise<unit>,
  deploy: deployment => promise<unit>,
  deployment: float => promise<option<deployment>>,
}

// The key is the control's own until the keys library derives it from the masters.
// RFCs fhg6w and b8f35 hold that step.
/** A record's secret sealed for its place. */
let sealed = (sealing, ~kind, ~id, secret) =>
  Sealing.seal(sealing, ~kind, ~id, ~field="secret", secret)

/** Thrown before any write where the secret could not be sealed, no key given or not 32 bytes. */
let sealable = async (sealing, ~kind, secret) => {
  // Id 0 is no record's, and this seal is never kept.
  let _: string = await sealed(sealing, ~kind, ~id=0., secret)
}

/**
 * A record's secret read, a plain one handed to `writeBack` sealed where one is given, an empty one
 * a fault and never a secret.
 */
let opened = async (sealing, ~kind, ~id, text, ~writeBack=?) => {
  if text == "" {
    JsError.throwWithMessage(`the ${kind} ${Float.toString(id)} holds an empty secret`)
  }
  switch await Sealing.read(sealing, ~kind, ~id, ~field="secret", text) {
  | Opened(secret) => secret
  | Plain(secret) =>
    switch writeBack {
    | Some(writeBack) => await writeBack(await sealed(sealing, ~kind, ~id, secret))
    | None => ()
    }
    secret
  }
}

/** Rows as D1 answers them, a column with no value `null`. */
type idRow = {id: float}
type organizationRow = {id: float, secret: Nullable.t<string>}
type bindingRow = {
  id: float,
  organization: float,
  secret: string,
  tunnel: Nullable.t<string>,
  address: Nullable.t<string>,
  origin: Nullable.t<string>,
  relayed: float,
  bound: Nullable.t<float>,
}

let bindingColumns = "id, organization, secret, tunnel, address, origin, relayed, bound"

type releaseRow = {hash: string, form: string, size: float, kinds: Nullable.t<string>}
type deploymentRow = {
  app: float,
  binding: float,
  release: string,
  capacity: float,
  kind: Nullable.t<string>,
}

let formName = (form: DeploymentForm.t) =>
  switch form {
  | Modules => "modules"
  | Component => "component"
  | Image => "image"
  }

let formOf = name =>
  switch name {
  | "component" => Some(DeploymentForm.Component)
  | "image" => Some(Image)
  | "modules" => Some(Modules)
  | _ => None
  }

let kindName = (kind: DeploymentKind.t) => (kind :> string)

let kindOf = name =>
  switch name {
  | "function" => Some(DeploymentKind.Function)
  | "instance" => Some(Instance)
  | "container" => Some(Container)
  | _ => None
  }

/** Kinds read by their names, none where one is no kind's. */
let kindsOf = names => {
  let kinds = names->Array.filterMap(kindOf)
  kinds->Array.length == names->Array.length ? Some(kinds) : None
}

/** A release's kinds as D1 keeps them, their names joined by commas, an empty list as ''. */
let kindsText = kinds => kinds->Array.map(kindName)->Array.join(",")

let kindsOfText = text => text == "" ? Some([]) : kindsOf(text->String.split(","))

/** Whether a deployment row ran, as `ran` reads a deployment. */
let ranRow = "(kind IS NOT NULL OR capacity != 0)"

/**
 * The next id of a table, as `n`'s greatest, counted on past every id an app or a binding holds.
 */
let following = table =>
  `WITH RECURSIVE n(v) AS (SELECT COALESCE(MAX(id), 0) + 1 FROM ${table}
  UNION ALL SELECT v + 1 FROM n
  WHERE EXISTS (SELECT 1 FROM app WHERE id = v) OR EXISTS (SELECT 1 FROM deployment WHERE app = v)
  OR EXISTS (SELECT 1 FROM binding WHERE id = v))`

/** The lowest address of the range no binding holds, as `a`'s one row. */
let unaddressed = `WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n
  WHERE v < ${Int.toString(Addresses.count)}),
  a(address) AS (SELECT '10.200.' || (v / 256) || '.' || (v % 256) FROM n
  WHERE '10.200.' || (v / 256) || '.' || (v % 256)
  NOT IN (SELECT address FROM binding WHERE address IS NOT NULL) ORDER BY v LIMIT 1)`

type addressRow = {address: Nullable.t<string>}

/** Whether the app a parameter names is held, its record kept or a deployment kept that ran. */
let appHeld = app =>
  `(EXISTS (SELECT 1 FROM app WHERE id = ${app})
  OR EXISTS (SELECT 1 FROM deployment WHERE app = ${app} AND ${ranRow}))`

/** The order a binding is given its address in, after every one given before, RFC rxmd9. */
let followingBound = "(SELECT COALESCE(MAX(bound), 0) + 1 FROM binding)"

let ofDatabase = (database, ~sealing) => {
  let statement = (sql, values) => database->Stores.prepare(sql)->Stores.bind(values)
  let first = async (sql, values) => (await statement(sql, values)->Stores.first)->Nullable.toOption
  let run = (sql, values) => statement(sql, values)->Stores.run
  // A plain secret is written back only where it is still kept plain.
  let secretOf = (~kind, ~id, text) =>
    opened(sealing, ~kind, ~id, text, ~writeBack=seal =>
      run(
        `UPDATE ${kind} SET secret = ? WHERE id = ? AND secret = ?`,
        [Text(seal), Number(id), Text(text)],
      )
    )
  let bindingOf = async (row: bindingRow): binding => {
    id: row.id,
    organization: row.organization,
    secret: await secretOf(~kind="binding", ~id=row.id, row.secret),
    tunnel: row.tunnel->Nullable.toOption,
    address: row.address->Nullable.toOption,
    origin: row.origin->Nullable.toOption,
    relayed: row.relayed != 0.,
    bound: row.bound->Nullable.toOption,
  }
  let bindingAt = async (sql, values) =>
    switch await first(sql, values) {
    | Some(row) => Some(await bindingOf(row))
    | None => None
    }
  let organizationAt = id => first("SELECT id, secret FROM organization WHERE id = ?", [Number(id)])
  {
    openOrganization: async (label, ~secret) => {
      await sealable(sealing, ~kind="organization", secret)
      await run(
        `${following("organization")} INSERT INTO organization (id, label) SELECT MAX(v), ? FROM n
        WHERE true ON CONFLICT (label) DO NOTHING`,
        [Text(label)],
      )
      switch await first("SELECT id, secret FROM organization WHERE label = ?", [Text(label)]) {
      | Some({id, secret: kept}: organizationRow) =>
        if kept->Nullable.toOption == None {
          let seal = await sealed(sealing, ~kind="organization", ~id, secret)
          await run(
            "UPDATE organization SET secret = ? WHERE id = ? AND secret IS NULL",
            [Text(seal), Number(id)],
          )
        }
        // Another call may have kept its secret first, so the one kept is read.
        switch (await organizationAt(id))->Option.flatMap(({secret}: organizationRow) =>
          secret->Nullable.toOption
        ) {
        | Some(text) => {id, secret: await secretOf(~kind="organization", ~id, text)}
        | None => JsError.throwWithMessage(`organization ${label} holds no secret once opened`)
        }
      | None => JsError.throwWithMessage(`no organization holds ${label} once opened`)
      }
    },
    hasOrganization: async id =>
      switch await first("SELECT id FROM organization WHERE id = ?", [Number(id)]) {
      | Some(_: idRow) => true
      | None => false
      },
    organizationSecret: async id =>
      switch (await organizationAt(id))->Option.flatMap(({secret}: organizationRow) =>
        secret->Nullable.toOption
      ) {
      | Some(text) => Some(await secretOf(~kind="organization", ~id, text))
      | None => None
      },
    openBinding: async (~organization, ~secret, ~relayed, ~random) => {
      await sealable(sealing, ~kind="binding", secret)
      let written = async id => {
        let seal = await sealed(sealing, ~kind="binding", ~id, secret)
        await run("UPDATE binding SET secret = ? WHERE id = ?", [Text(seal), Number(id)])
      }
      // One statement, so no id of any kind can be taken between its check and its insert.
      let id = await Ids.drawn(~random, ~kind="binding", async id =>
        switch await first(
          "INSERT INTO binding (id, organization, secret, relayed) SELECT ?1, ?2, '', ?3
          WHERE NOT EXISTS (SELECT 1 FROM app WHERE id = ?1)
          AND NOT EXISTS (SELECT 1 FROM organization WHERE id = ?1)
          AND NOT EXISTS (SELECT 1 FROM deployment WHERE app = ?1)
          ON CONFLICT (id) DO NOTHING RETURNING id",
          [Number(id), Number(organization), Number(relayed ? 1. : 0.)],
        ) {
        | Some(_: idRow) => true
        | None => false
        }
      )
      // Any failure after the insert deletes the row, so none is left with an empty secret.
      switch await written(id) {
      | () => id
      | exception JsExn(e) =>
        await run("DELETE FROM binding WHERE id = ?", [Number(id)])
        throw(JsExn(e))
      }
    },
    binding: id => bindingAt(`SELECT ${bindingColumns} FROM binding WHERE id = ?`, [Number(id)]),
    storage: organization =>
      bindingAt(
        `SELECT ${bindingColumns} FROM binding
        WHERE organization = ? AND relayed = 0 AND bound IS NOT NULL AND origin IS NULL
        ORDER BY bound LIMIT 1`,
        [Number(organization)],
      ),
    addressedAt: address =>
      bindingAt(`SELECT ${bindingColumns} FROM binding WHERE address = ?`, [Text(address)]),
    tunneled: (~binding, ~tunnel) =>
      run("UPDATE binding SET tunnel = ? WHERE id = ?", [Text(tunnel), Number(binding)]),
    // Taken and written in one statement, so no two bindings are given one address.
    addressed: async (~binding, ~address=?) => {
      let taken = switch address {
      | Some(given) =>
        first(
          "UPDATE binding SET address = ? WHERE id = ? AND address IS NULL AND origin IS NULL
          RETURNING address",
          [Text(given), Number(binding)],
        )
      | None =>
        first(
          `${unaddressed} UPDATE binding SET address = (SELECT address FROM a)
          WHERE id = ? AND address IS NULL AND origin IS NULL AND EXISTS (SELECT 1 FROM a)
          RETURNING address`,
          [Number(binding)],
        )
      }
      switch await taken {
      | Some({address}: addressRow) => address->Nullable.toOption
      | None =>
        (
          await first("SELECT address FROM binding WHERE id = ?", [Number(binding)])
        )->Option.flatMap(({address}: addressRow) => address->Nullable.toOption)
      }
    },
    // Given back only where it still holds that one unbound, as it was taken.
    unaddressed: (~binding, ~address) =>
      run(
        "UPDATE binding SET address = NULL WHERE id = ? AND address = ? AND bound IS NULL",
        [Number(binding), Text(address)],
      ),
    // Its order taken in the statement that writes it, after every one bound before.
    routed: (~binding) =>
      run(
        `UPDATE binding SET bound = ${followingBound}
        WHERE id = ? AND address IS NOT NULL AND bound IS NULL AND origin IS NULL`,
        [Number(binding)],
      ),
    // Written only where no bind fixed its reach first, so one of two binds at once wins.
    originated: async (~binding, ~origin) =>
      switch await first(
        "UPDATE binding SET origin = ? WHERE id = ? AND origin IS NULL AND bound IS NULL
        RETURNING id",
        [Text(origin), Number(binding)],
      ) {
      | Some(_: idRow) => true
      | None => false
      },
    putRelease: release =>
      run(
        "INSERT INTO release (hash, form, size, kinds) VALUES (?, ?, ?, ?)
        ON CONFLICT (hash) DO NOTHING",
        [
          Text(release.hash),
          Text(formName(release.form)),
          Number(release.size),
          release.kinds->Option.mapOr(Stores.Null, kinds => Text(kindsText(kinds))),
        ],
      ),
    release: async hash =>
      (
        await first("SELECT hash, form, size, kinds FROM release WHERE hash = ?", [Text(hash)])
      )->Option.flatMap((row: releaseRow) =>
        switch (formOf(row.form), row.kinds->Nullable.toOption) {
        | (Some(form), None) => Some(({hash: row.hash, form, size: row.size, kinds: None}: release))
        | (Some(form), Some(text)) =>
          kindsOfText(text)->Option.map((kinds): release => {
            hash: row.hash,
            form,
            size: row.size,
            kinds: Some(kinds),
          })
        | (None, _) => None
        }
      ),
    // Written only where the app is held, so a forgotten app's deploy never lands.
    deploy: d =>
      run(
        `INSERT INTO deployment (app, binding, release, capacity, kind) SELECT ?1, ?2, ?3, ?4, ?5
        WHERE ${appHeld("?1")} ON CONFLICT (app) DO UPDATE SET binding = excluded.binding,
        release = excluded.release, capacity = excluded.capacity, kind = excluded.kind`,
        [
          Number(d.app),
          Number(d.binding),
          Text(d.release),
          Number(d.capacity),
          d.kind->Option.mapOr(Stores.Null, kind => Text(kindName(kind))),
        ],
      ),
    // A kind kept that names no kind reads as no deployment, as an unknown form reads no release.
    deployment: async app =>
      (
        await first(
          "SELECT app, binding, release, capacity, kind FROM deployment WHERE app = ?",
          [Number(app)],
        )
      )->Option.flatMap((row: deploymentRow) => {
        let {app, binding, release, capacity} = row
        switch row.kind->Nullable.toOption->Option.map(kindOf) {
        | None => Some(({app, binding, release, capacity, kind: None}: deployment))
        | Some(Some(kind)) =>
          Some(({app, binding, release, capacity, kind: Some(kind)}: deployment))
        | Some(None) => None
        }
      }),
    // One statement, so no id of any kind can be taken between its check and its insert.
    drawApp: (~random) =>
      Ids.drawn(~random, ~kind="app", async id =>
        switch await first(
          "INSERT INTO app (id) SELECT ?1 WHERE NOT EXISTS (SELECT 1 FROM binding WHERE id = ?1)
          AND NOT EXISTS (SELECT 1 FROM organization WHERE id = ?1)
          AND NOT EXISTS (SELECT 1 FROM deployment WHERE app = ?1)
          ON CONFLICT (id) DO NOTHING RETURNING id",
          [Number(id)],
        ) {
        | Some(_: idRow) => true
        | None => false
        }
      ),
    // The deployment goes first, and the app only where none is left, so a deploy declaring its
    // kind between the two statements keeps both, and one after them finds the app gone.
    forgetApp: async app => {
      let deleted = await first(
        `DELETE FROM deployment WHERE app = ? AND NOT ${ranRow} RETURNING app`,
        [Number(app)],
      )
      switch await first(
        "DELETE FROM app WHERE id = ?1
        AND NOT EXISTS (SELECT 1 FROM deployment WHERE app = ?1) RETURNING id",
        [Number(app)],
      ) {
      | Some(_: idRow) => true
      // A deployment that never ran kept with no app record is forgotten alike.
      | None =>
        deleted->Option.isSome &&
          (await first(`SELECT 1 AS id WHERE ${appHeld("?1")}`, [Number(app)]))->Option.isNone
      }
    },
    hasApp: async app => {
      let row: option<idRow> = await first("SELECT id FROM app WHERE id = ?", [Number(app)])
      row->Option.isSome
    },
    retireApp: async app => {
      await run("DELETE FROM app WHERE id = ?", [Number(app)])
      await run("DELETE FROM deployment WHERE app = ?", [Number(app)])
    },
  }
}

/** What the store answered, thrown where it did not answer, as the API answers what throws. */
let held = result =>
  switch result {
  | Ok(value) => value
  | Error(why) => JsError.throwWithMessage(`the objects were not reached, ${why}`)
  }

let field = (json, name) => json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))
let number = (json, name) => json->field(name)->Option.flatMap(JSON.Decode.float)
let text = (json, name) => json->field(name)->Option.flatMap(JSON.Decode.string)

let organizationJson = (id, label, sealed) => JSON.Object(
  dict{
    "id": Number(id),
    "label": String(label),
    "secret": String(sealed),
  },
)

let bindingJson = (b: binding, sealed) => {
  let o = dict{
    "id": JSON.Number(b.id),
    "organization": Number(b.organization),
    "secret": String(sealed),
    "relayed": Boolean(b.relayed),
  }
  // Written even where none, so a record with no field at all is one kept before the order was.
  o->Dict.set("bound", b.bound->Option.mapOr(JSON.Null, n => JSON.Number(n)))
  b.tunnel->Option.forEach(t => o->Dict.set("tunnel", String(t)))
  b.address->Option.forEach(a => o->Dict.set("address", String(a)))
  b.origin->Option.forEach(a => o->Dict.set("origin", String(a)))
  JSON.Object(o)
}

let ofObjects = (objects: Objects.t, ~sealing) => {
  let readJson = async name =>
    held(await objects.read(name))->Option.map(bytes => JSON.parseOrThrow(Web.fromUtf8(bytes)))
  let writeJson = async (name, json) =>
    held(await objects.write(name, Web.utf8(JSON.stringify(json))))
  // A record is read by the id its path names, a document holding another id a fault.
  let record = async (name, id) =>
    switch await readJson(name) {
    | Some(json) if json->number("id") == Some(id) => Some(json)
    | Some(_) => JsError.throwWithMessage(`the record at ${name} holds another id than its path's`)
    | None => None
    }
  let idOf = name =>
    switch name
    ->String.split("/")
    ->Array.at(-1)
    ->Option.filter(last => /^[0-9]+$/->RegExp.test(last))
    ->Option.flatMap(Float.fromString) {
    | Some(id) => id
    | None => JsError.throwWithMessage(`the record at ${name} is named by no id`)
    }
  let every = async prefix =>
    (
      await Promise.all(
        held(await objects.list(prefix))->Array.map(async name => {
          let id = idOf(name)
          (await record(name, id))->Option.map(json => (id, json))
        }),
      )
    )->Array.filterMap(j => j)
  // Ids are given one at a time within a request, a state being built for each, RFC rxmd9.
  let queue = ref(Promise.resolve())
  let serial = f => {
    let run = queue.contents->Promise.then(() => f())
    queue := run->Promise.then(_ => Promise.resolve())->Promise.catch(_ => Promise.resolve())
    run
  }
  // The id after the greatest, counted on past every id an app or a binding holds.
  let rec past = async id =>
    switch await Promise.all([
      readJson(`state/apps/${Float.toString(id)}`),
      readJson(`state/deployments/${Float.toString(id)}`),
      readJson(`state/bindings/${Float.toString(id)}`),
    ]) {
    | [None, None, None] => id
    | _ => await past(id +. 1.)
    }
  let next = all => past(all->Array.reduce(0., (most, (id, _)) => Math.max(most, id)) +. 1.)
  let organizationAt = id => `state/organizations/${Float.toString(id)}`
  let bindingAt = id => `state/bindings/${Float.toString(id)}`
  // An organization's plain secret is written back, since no write but its opening changes it.
  // A binding's is not, since worker.res builds a state per request and another may write it.
  // A binding's plain secret is sealed at the binding's next write, `changed` below.
  let replaced = async (id, plain, seal) =>
    switch await record(organizationAt(id), id) {
    | Some(json) if json->text("secret") == Some(plain) =>
      let o = json->JSON.Decode.object->Option.getOr(dict{})->Dict.copy
      o->Dict.set("secret", JSON.String(seal))
      await writeJson(organizationAt(id), JSON.Object(o))
    | Some(_) | None => ()
    }
  let bindingFromJson = async (~id, json) =>
    switch (json->number("organization"), json->text("secret")) {
    | (Some(organization), Some(kept)) =>
      let secret = await opened(sealing, ~kind="binding", ~id, kept)
      Some(
        (
          {
            id,
            organization,
            secret,
            tunnel: json->text("tunnel"),
            address: json->text("address"),
            origin: json->text("origin"),
            relayed: json->field("relayed")->Option.flatMap(JSON.Decode.bool)->Option.getOr(false),
            // A record kept with an address before the order was is bound by its id, as 0006 does.
            bound: switch json->field("bound") {
            | Some(order) => order->JSON.Decode.float
            | None => json->text("address")->Option.map(_ => id)
            },
          }: binding
        ),
      )
    | _ => None
    }
  let binding = async id =>
    switch await record(bindingAt(id), id) {
    | Some(json) => await bindingFromJson(~id, json)
    | None => None
    }
  let bindings = async () =>
    (
      await Promise.all(
        (await every("state/bindings/"))->Array.map(((id, json)) => bindingFromJson(~id, json)),
      )
    )->Array.filterMap(b => b)
  let writeBinding = async (b: binding) =>
    await writeJson(
      bindingAt(b.id),
      bindingJson(b, await sealed(sealing, ~kind="binding", ~id=b.id, b.secret)),
    )
  let changed = (id, f) =>
    serial(async () =>
      switch await record(bindingAt(id), id) {
      | Some(json) =>
        // Written whole and sealed below, so a plain secret read here is sealed as it is written.
        switch await bindingFromJson(~id, json) {
        | Some(b) => await writeBinding(f(b))
        | None => ()
        }
      | None => ()
      }
    )
  let organization = id => record(organizationAt(id), id)
  {
    openOrganization: (label, ~secret) =>
      serial(async () => {
        await sealable(sealing, ~kind="organization", secret)
        let all = await every("state/organizations/")
        switch all->Array.find(((_, json)) => json->text("label") == Some(label)) {
        | Some((id, json)) =>
          switch json->text("secret") {
          | Some(kept) =>
            let secret = await opened(sealing, ~kind="organization", ~id, kept, ~writeBack=seal =>
              replaced(id, kept, seal)
            )
            ({id, secret}: organization)
          | None =>
            await writeJson(
              organizationAt(id),
              organizationJson(id, label, await sealed(sealing, ~kind="organization", ~id, secret)),
            )
            ({id, secret}: organization)
          }
        | None =>
          let id = await next(all)
          await writeJson(
            organizationAt(id),
            organizationJson(id, label, await sealed(sealing, ~kind="organization", ~id, secret)),
          )
          ({id, secret}: organization)
        }
      }),
    hasOrganization: async id => (await organization(id))->Option.isSome,
    organizationSecret: async id =>
      switch (await organization(id))->Option.flatMap(json => json->text("secret")) {
      | Some(kept) =>
        Some(
          await opened(sealing, ~kind="organization", ~id, kept, ~writeBack=seal =>
            serial(() => replaced(id, kept, seal))
          ),
        )
      | None => None
      },
    // Checked and written within the queue, as an app's id is drawn.
    openBinding: (~organization, ~secret, ~relayed, ~random) =>
      serial(async () => {
        await sealable(sealing, ~kind="binding", secret)
        await Ids.drawn(~random, ~kind="binding", async id => {
          let held = [
            bindingAt(id),
            `state/apps/${Float.toString(id)}`,
            organizationAt(id),
            `state/deployments/${Float.toString(id)}`,
          ]
          switch await Promise.all(held->Array.map(readJson)) {
          | found if found->Array.every(Option.isNone) =>
            await writeBinding({
              id,
              organization,
              secret,
              tunnel: None,
              address: None,
              origin: None,
              relayed,
              bound: None,
            })
            true
          | _ => false
          }
        })
      }),
    binding,
    storage: async organization =>
      (await bindings())
      ->Array.filterMap(b =>
        b.organization == organization && !b.relayed && b.origin == None
          ? b.bound->Option.map(order => (order, b))
          : None
      )
      ->Array.toSorted(((a, _), (b, _)) => a -. b)
      ->Array.get(0)
      ->Option.map(((_, b)) => b),
    addressedAt: async address => (await bindings())->Array.find(b => b.address == Some(address)),
    tunneled: (~binding, ~tunnel) => changed(binding, b => {...b, tunnel: Some(tunnel)}),
    // Taken within the queue, which orders one request's calls alone, as a state is built for each.
    // Two requests at once may each take one address, as D1's one statement never does.
    addressed: (~binding as id, ~address as given=?) =>
      serial(async () =>
        switch await binding(id) {
        | Some({address: Some(address)}) => Some(address)
        | Some(b) if b.origin == None =>
          let chosen = switch given {
          | Some(given) => Some(given)
          | None => Addresses.lowest((await bindings())->Array.filterMap(b => b.address))
          }
          switch chosen {
          | Some(address) =>
            await writeBinding({...b, address: Some(address)})
            Some(address)
          | None => None
          }
        | Some(_) | None => None
        }
      ),
    unaddressed: (~binding as id, ~address) =>
      serial(async () =>
        switch await binding(id) {
        | Some(b) if b.address == Some(address) && b.bound == None =>
          await writeBinding({...b, address: None})
        | Some(_) | None => ()
        }
      ),
    routed: (~binding as id) =>
      serial(async () =>
        switch await binding(id) {
        | Some({address: Some(_), bound: None, origin: None} as b) =>
          let order = (await bindings())->Array.filterMap(b => b.bound)->Array.reduce(0., Math.max)
          await writeBinding({...b, bound: Some(order +. 1.)})
        | Some(_) | None => ()
        }
      ),
    originated: (~binding as id, ~origin) =>
      serial(async () =>
        switch await binding(id) {
        | Some(b) if b.origin == None && b.bound == None =>
          await writeBinding({...b, origin: Some(origin)})
          true
        | Some(_) | None => false
        }
      ),
    putRelease: async release => {
      let name = `state/releases/${release.hash}`
      if (await readJson(name))->Option.isNone {
        let o = dict{
          "hash": JSON.String(release.hash),
          "form": String(formName(release.form)),
          "size": Number(release.size),
        }
        release.kinds->Option.forEach(kinds =>
          o->Dict.set("kinds", Array(kinds->Array.map(kind => JSON.String(kindName(kind)))))
        )
        await writeJson(name, JSON.Object(o))
      }
    },
    release: async hash =>
      (await readJson(`state/releases/${hash}`))->Option.flatMap(json => {
        let kinds =
          json
          ->field("kinds")
          ->Option.map(kinds =>
            kinds
            ->JSON.Decode.array
            ->Option.flatMap(
              names => {
                let texts = names->Array.filterMap(JSON.Decode.string)
                texts->Array.length == names->Array.length ? kindsOf(texts) : None
              },
            )
          )
        switch (json->text("form")->Option.flatMap(formOf), json->number("size"), kinds) {
        | (Some(form), Some(size), None) => Some(({hash, form, size, kinds: None}: release))
        | (Some(form), Some(size), Some(Some(kinds))) =>
          Some(({hash, form, size, kinds: Some(kinds)}: release))
        | _ => None
        }
      }),
    // Written within the queue only where the app is held, as D1 writes it.
    deploy: d =>
      serial(async () => {
        let at = `state/deployments/${Float.toString(d.app)}`
        switch await Promise.all([readJson(`state/apps/${Float.toString(d.app)}`), readJson(at)]) {
        | [None, None] => ()
        | [None, Some(json)]
          if json->text("kind") == None && json->number("capacity")->Option.getOr(0.) == 0. => ()
        | _ =>
          let o = dict{
            "app": JSON.Number(d.app),
            "binding": Number(d.binding),
            "release": String(d.release),
            "capacity": Number(d.capacity),
          }
          d.kind->Option.forEach(kind => o->Dict.set("kind", String(kindName(kind))))
          await writeJson(at, JSON.Object(o))
        }
      }),
    deployment: async app =>
      (await readJson(`state/deployments/${Float.toString(app)}`))->Option.flatMap(json =>
        switch (
          json->number("binding"),
          json->text("release"),
          json->number("capacity"),
          json->text("kind")->Option.map(kindOf),
        ) {
        | (Some(binding), Some(release), Some(capacity), None) =>
          Some(({app, binding, release, capacity, kind: None}: deployment))
        | (Some(binding), Some(release), Some(capacity), Some(Some(kind))) =>
          Some(({app, binding, release, capacity, kind: Some(kind)}: deployment))
        | _ => None
        }
      ),
    // Checked and written within the queue, as a binding's id is drawn.
    drawApp: (~random) =>
      serial(() =>
        Ids.drawn(~random, ~kind="app", async id => {
          let at = `state/apps/${Float.toString(id)}`
          let held = [
            at,
            organizationAt(id),
            bindingAt(id),
            `state/deployments/${Float.toString(id)}`,
          ]
          switch await Promise.all(held->Array.map(readJson)) {
          | found if found->Array.every(Option.isNone) =>
            await writeJson(at, JSON.Object(dict{"id": JSON.Number(id)}))
            true
          | _ => false
          }
        })
      ),
    // The deployment goes before the app, so an id is held until both are gone.
    forgetApp: app =>
      serial(async () => {
        let at = `state/apps/${Float.toString(app)}`
        let deploymentAt = `state/deployments/${Float.toString(app)}`
        switch await Promise.all([readJson(at), readJson(deploymentAt)]) {
        | [None, None] => false
        | [_, Some(json)]
          if json->text("kind") != None || json->number("capacity") != Some(0.) => false
        | _ =>
          held(await objects.delete(deploymentAt))
          held(await objects.delete(at))
          // A control stood on that answers a delete as done while keeping the object is a fault.
          switch await Promise.all([readJson(at), readJson(deploymentAt)]) {
          | [None, None] => true
          | _ => JsError.throwWithMessage(`app ${Ids.text(app)} is still kept once deleted`)
          }
        }
      }),
    hasApp: async app => (await readJson(`state/apps/${Float.toString(app)}`))->Option.isSome,
    // Taken within the queue as a forget is, the record before the deployment.
    retireApp: app =>
      serial(async () => {
        let at = `state/apps/${Float.toString(app)}`
        let deploymentAt = `state/deployments/${Float.toString(app)}`
        held(await objects.delete(at))
        held(await objects.delete(deploymentAt))
        switch await Promise.all([readJson(at), readJson(deploymentAt)]) {
        | [None, None] => ()
        | _ => JsError.throwWithMessage(`app ${Ids.text(app)} is still kept once deleted`)
        }
      }),
  }
}
