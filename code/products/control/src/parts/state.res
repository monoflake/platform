module DeploymentForm = Envelope.Contracts.DeploymentForm

type binding = {
  id: float,
  organization: float,
  secret: Uint8Array.t,
  tunnel: option<string>,
  address: option<string>,
  relayed: bool,
}

type organization = {id: float, secret: Uint8Array.t}

type release = {hash: string, form: DeploymentForm.t, size: float}

type deployment = {app: float, binding: float, release: string, capacity: float}

type t = {
  openOrganization: (string, ~secret: Uint8Array.t) => promise<organization>,
  hasOrganization: float => promise<bool>,
  organizationSecret: float => promise<option<Uint8Array.t>>,
  openBinding: (~organization: float, ~secret: Uint8Array.t, ~relayed: bool) => promise<float>,
  binding: float => promise<option<binding>>,
  storage: float => promise<option<binding>>,
  addressedAt: string => promise<option<binding>>,
  tunneled: (~binding: float, ~tunnel: string) => promise<unit>,
  addressed: (~binding: float, ~address: string) => promise<unit>,
  putRelease: release => promise<unit>,
  release: string => promise<option<release>>,
  deploy: deployment => promise<unit>,
  deployment: float => promise<option<deployment>>,
}

// The key is a secret of the control's own until the keys library derives it from the masters, RFCs fhg6w and b8f35.
/** A record's secret sealed for its place. */
let sealed = (sealing, ~kind, ~id, secret) =>
  Sealing.seal(sealing, ~kind, ~id, ~field="secret", secret)

/**
 * A record's secret read, a plain one handed to `writeBack` sealed, an empty one a fault and never
 * a secret.
 */
let opened = async (sealing, ~kind, ~id, text, ~writeBack) => {
  if text == "" {
    JsError.throwWithMessage(`the ${kind} ${Float.toString(id)} holds an empty secret`)
  }
  switch await Sealing.read(sealing, ~kind, ~id, ~field="secret", text) {
  | Opened(secret) => secret
  | Plain(secret) =>
    await writeBack(await sealed(sealing, ~kind, ~id, secret))
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
  relayed: float,
}

let bindingColumns = "id, organization, secret, tunnel, address, relayed"

type releaseRow = {hash: string, form: string, size: float}
type deploymentRow = {app: float, binding: float, release: string, capacity: float}

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
    relayed: row.relayed != 0.,
  }
  let bindingAt = async (sql, values) =>
    switch await first(sql, values) {
    | Some(row) => Some(await bindingOf(row))
    | None => None
    }
  let organizationAt = id => first("SELECT id, secret FROM organization WHERE id = ?", [Number(id)])
  {
    openOrganization: async (label, ~secret) => {
      await run(
        "INSERT INTO organization (label) VALUES (?) ON CONFLICT (label) DO NOTHING",
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
    openBinding: async (~organization, ~secret, ~relayed) =>
      switch await first(
        "INSERT INTO binding (organization, secret, relayed) VALUES (?, '', ?) RETURNING id",
        [Number(organization), Number(relayed ? 1. : 0.)],
      ) {
      | Some({id}: idRow) =>
        // The id is known only once inserted, so its secret is sealed for it after.
        switch await sealed(sealing, ~kind="binding", ~id, secret) {
        | seal =>
          await run("UPDATE binding SET secret = ? WHERE id = ?", [Text(seal), Number(id)])
          id
        | exception JsExn(e) =>
          await run("DELETE FROM binding WHERE id = ?", [Number(id)])
          throw(JsExn(e))
        }
      | None => JsError.throwWithMessage("no binding inserted")
      },
    binding: id => bindingAt(`SELECT ${bindingColumns} FROM binding WHERE id = ?`, [Number(id)]),
    storage: organization =>
      bindingAt(
        `SELECT ${bindingColumns} FROM binding
        WHERE organization = ? AND relayed = 0 AND address IS NOT NULL ORDER BY id LIMIT 1`,
        [Number(organization)],
      ),
    addressedAt: address =>
      bindingAt(`SELECT ${bindingColumns} FROM binding WHERE address = ?`, [Text(address)]),
    tunneled: (~binding, ~tunnel) =>
      run("UPDATE binding SET tunnel = ? WHERE id = ?", [Text(tunnel), Number(binding)]),
    addressed: (~binding, ~address) =>
      run("UPDATE binding SET address = ? WHERE id = ?", [Text(address), Number(binding)]),
    putRelease: release =>
      run(
        "INSERT INTO release (hash, form, size) VALUES (?, ?, ?) ON CONFLICT (hash) DO NOTHING",
        [Text(release.hash), Text(formName(release.form)), Number(release.size)],
      ),
    release: async hash =>
      (
        await first("SELECT hash, form, size FROM release WHERE hash = ?", [Text(hash)])
      )->Option.flatMap((row: releaseRow) =>
        formOf(row.form)->Option.map((form): release => {hash: row.hash, form, size: row.size})
      ),
    deploy: d =>
      run(
        "INSERT INTO deployment (app, binding, release, capacity) VALUES (?, ?, ?, ?)
        ON CONFLICT (app) DO UPDATE SET binding = excluded.binding, release = excluded.release,
        capacity = excluded.capacity",
        [Number(d.app), Number(d.binding), Text(d.release), Number(d.capacity)],
      ),
    deployment: async app =>
      (
        await first(
          "SELECT app, binding, release, capacity FROM deployment WHERE app = ?",
          [Number(app)],
        )
      )->Option.map((row: deploymentRow): deployment => {
        app: row.app,
        binding: row.binding,
        release: row.release,
        capacity: row.capacity,
      }),
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
  b.tunnel->Option.forEach(t => o->Dict.set("tunnel", String(t)))
  b.address->Option.forEach(a => o->Dict.set("address", String(a)))
  JSON.Object(o)
}

let ofObjects = (objects: Objects.t, ~sealing) => {
  let readJson = async name =>
    held(await objects.read(name))->Option.map(bytes => JSON.parseOrThrow(Web.fromUtf8(bytes)))
  let writeJson = async (name, json) =>
    held(await objects.write(name, Web.utf8(JSON.stringify(json))))
  let every = async prefix =>
    (await Promise.all(held(await objects.list(prefix))->Array.map(readJson)))->Array.filterMap(j =>
      j
    )
  // Ids are given one at a time, as one process serves this control, RFC rxmd9.
  let queue = ref(Promise.resolve())
  let serial = f => {
    let run = queue.contents->Promise.then(() => f())
    queue := run->Promise.then(_ => Promise.resolve())->Promise.catch(_ => Promise.resolve())
    run
  }
  let next = all =>
    all->Array.reduce(0., (most, json) =>
      Math.max(most, json->number("id")->Option.getOr(0.))
    ) +. 1.
  let organizationAt = id => `state/organizations/${Float.toString(id)}`
  let bindingAt = id => `state/bindings/${Float.toString(id)}`
  // A record's secret replaced only where it still holds the plain one read.
  let replaced = async (name, plain, seal) =>
    switch await readJson(name) {
    | Some(json) if json->text("secret") == Some(plain) =>
      let o = json->JSON.Decode.object->Option.getOr(dict{})->Dict.copy
      o->Dict.set("secret", JSON.String(seal))
      await writeJson(name, JSON.Object(o))
    | Some(_) | None => ()
    }
  let rewritten = (name, plain, seal) => serial(() => replaced(name, plain, seal))
  let bindingFromJson = async (json, ~writeBack) =>
    switch (json->number("id"), json->number("organization"), json->text("secret")) {
    | (Some(id), Some(organization), Some(kept)) =>
      let secret = await opened(sealing, ~kind="binding", ~id, kept, ~writeBack=seal =>
        writeBack(bindingAt(id), kept, seal)
      )
      Some(
        (
          {
            id,
            organization,
            secret,
            tunnel: json->text("tunnel"),
            address: json->text("address"),
            relayed: json->field("relayed")->Option.flatMap(JSON.Decode.bool)->Option.getOr(false),
          }: binding
        ),
      )
    | _ => None
    }
  let binding = async id =>
    switch await readJson(bindingAt(id)) {
    | Some(json) => await bindingFromJson(json, ~writeBack=rewritten)
    | None => None
    }
  let bindings = async () =>
    (
      await Promise.all(
        (await every("state/bindings/"))->Array.map(json =>
          bindingFromJson(json, ~writeBack=rewritten)
        ),
      )
    )->Array.filterMap(b => b)
  let writeBinding = async (b: binding) =>
    await writeJson(
      bindingAt(b.id),
      bindingJson(b, await sealed(sealing, ~kind="binding", ~id=b.id, b.secret)),
    )
  let changed = (id, f) =>
    serial(async () =>
      switch await readJson(bindingAt(id)) {
      | Some(json) =>
        // Written whole and sealed below, so a plain secret read here needs no writing back.
        switch await bindingFromJson(json, ~writeBack=(_, _, _) => Promise.resolve()) {
        | Some(b) => await writeBinding(f(b))
        | None => ()
        }
      | None => ()
      }
    )
  let organization = async id => await readJson(organizationAt(id))
  {
    openOrganization: (label, ~secret) =>
      serial(async () => {
        let all = await every("state/organizations/")
        switch all->Array.find(json => json->text("label") == Some(label)) {
        | Some(json) =>
          let id = json->number("id")->Option.getOr(0.)
          switch json->text("secret") {
          | Some(kept) =>
            let secret = await opened(sealing, ~kind="organization", ~id, kept, ~writeBack=seal =>
              replaced(organizationAt(id), kept, seal)
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
          let id = next(all)
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
            rewritten(organizationAt(id), kept, seal)
          ),
        )
      | None => None
      },
    openBinding: (~organization, ~secret, ~relayed) =>
      serial(async () => {
        let id = next(await every("state/bindings/"))
        await writeBinding({id, organization, secret, tunnel: None, address: None, relayed})
        id
      }),
    binding,
    storage: async organization =>
      (await bindings())
      ->Array.filter(b => b.organization == organization && !b.relayed && b.address != None)
      ->Array.toSorted((a, b) => a.id -. b.id)
      ->Array.get(0),
    addressedAt: async address => (await bindings())->Array.find(b => b.address == Some(address)),
    tunneled: (~binding, ~tunnel) => changed(binding, b => {...b, tunnel: Some(tunnel)}),
    addressed: (~binding, ~address) => changed(binding, b => {...b, address: Some(address)}),
    putRelease: async release => {
      let name = `state/releases/${release.hash}`
      if (await readJson(name))->Option.isNone {
        await writeJson(
          name,
          JSON.Object(
            dict{
              "hash": String(release.hash),
              "form": String(formName(release.form)),
              "size": Number(release.size),
            },
          ),
        )
      }
    },
    release: async hash =>
      (await readJson(`state/releases/${hash}`))->Option.flatMap(json =>
        switch (json->text("form")->Option.flatMap(formOf), json->number("size")) {
        | (Some(form), Some(size)) => Some(({hash, form, size}: release))
        | _ => None
        }
      ),
    deploy: d =>
      writeJson(
        `state/deployments/${Float.toString(d.app)}`,
        JSON.Object(
          dict{
            "app": Number(d.app),
            "binding": Number(d.binding),
            "release": String(d.release),
            "capacity": Number(d.capacity),
          },
        ),
      ),
    deployment: async app =>
      (await readJson(`state/deployments/${Float.toString(app)}`))->Option.flatMap(json =>
        switch (json->number("binding"), json->text("release"), json->number("capacity")) {
        | (Some(binding), Some(release), Some(capacity)) =>
          Some(({app, binding, release, capacity}: deployment))
        | _ => None
        }
      ),
  }
}
