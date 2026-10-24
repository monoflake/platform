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

let bindingOf = (row: bindingRow) =>
  Envelope.Hex.decode(row.secret)->Option.map((secret): binding => {
    id: row.id,
    organization: row.organization,
    secret,
    tunnel: row.tunnel->Nullable.toOption,
    address: row.address->Nullable.toOption,
    relayed: row.relayed != 0.,
  })
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

let ofDatabase = database => {
  let statement = (sql, values) => database->Stores.prepare(sql)->Stores.bind(values)
  let first = async (sql, values) => (await statement(sql, values)->Stores.first)->Nullable.toOption
  let run = (sql, values) => statement(sql, values)->Stores.run
  {
    // FIXME fhg6w seals a secret under its control's key, which waits on that key being made.
    openOrganization: async (label, ~secret) => {
      let hex = Envelope.Hex.encode(secret)
      await run(
        "INSERT INTO organization (label, secret) VALUES (?, ?)
        ON CONFLICT (label) DO UPDATE SET secret = coalesce(organization.secret, excluded.secret)",
        [Text(label), Text(hex)],
      )
      switch await first("SELECT id, secret FROM organization WHERE label = ?", [Text(label)]) {
      | Some({id, secret}: organizationRow) =>
        switch secret->Nullable.toOption->Option.flatMap(Envelope.Hex.decode) {
        | Some(secret) => {id, secret}
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
      (
        await first("SELECT id, secret FROM organization WHERE id = ?", [Number(id)])
      )->Option.flatMap(({secret}: organizationRow) =>
        secret->Nullable.toOption->Option.flatMap(Envelope.Hex.decode)
      ),
    openBinding: async (~organization, ~secret, ~relayed) =>
      switch await first(
        "INSERT INTO binding (organization, secret, relayed) VALUES (?, ?, ?) RETURNING id",
        [Number(organization), Text(Envelope.Hex.encode(secret)), Number(relayed ? 1. : 0.)],
      ) {
      | Some({id}: idRow) => id
      | None => JsError.throwWithMessage("no binding inserted")
      },
    binding: async id =>
      (
        await first(`SELECT ${bindingColumns} FROM binding WHERE id = ?`, [Number(id)])
      )->Option.flatMap(bindingOf),
    storage: async organization =>
      (
        await first(
          `SELECT ${bindingColumns} FROM binding
          WHERE organization = ? AND relayed = 0 AND address IS NOT NULL ORDER BY id LIMIT 1`,
          [Number(organization)],
        )
      )->Option.flatMap(bindingOf),
    addressedAt: async address =>
      (
        await first(`SELECT ${bindingColumns} FROM binding WHERE address = ?`, [Text(address)])
      )->Option.flatMap(bindingOf),
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

let organizationJson = (id, label, secret) => JSON.Object(
  dict{
    "id": Number(id),
    "label": String(label),
    "secret": String(Envelope.Hex.encode(secret)),
  },
)

let bindingJson = (b: binding) => {
  let o = dict{
    "id": JSON.Number(b.id),
    "organization": Number(b.organization),
    "secret": String(Envelope.Hex.encode(b.secret)),
    "relayed": Boolean(b.relayed),
  }
  b.tunnel->Option.forEach(t => o->Dict.set("tunnel", String(t)))
  b.address->Option.forEach(a => o->Dict.set("address", String(a)))
  JSON.Object(o)
}

let bindingFromJson = json =>
  switch (
    json->number("id"),
    json->number("organization"),
    json->text("secret")->Option.flatMap(Envelope.Hex.decode),
  ) {
  | (Some(id), Some(organization), Some(secret)) =>
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

let ofObjects = (objects: Objects.t) => {
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
  let bindingAt = id => `state/bindings/${Float.toString(id)}`
  let binding = async id => (await readJson(bindingAt(id)))->Option.flatMap(bindingFromJson)
  let bindings = async () => (await every("state/bindings/"))->Array.filterMap(bindingFromJson)
  let changed = (id, f) =>
    serial(async () =>
      switch await binding(id) {
      | Some(b) => await writeJson(bindingAt(id), bindingJson(f(b)))
      | None => ()
      }
    )
  let organization = async id => await readJson(`state/organizations/${Float.toString(id)}`)
  {
    openOrganization: (label, ~secret) =>
      serial(async () => {
        let all = await every("state/organizations/")
        switch all->Array.find(json => json->text("label") == Some(label)) {
        | Some(json) =>
          let id = json->number("id")->Option.getOr(0.)
          switch json->text("secret")->Option.flatMap(Envelope.Hex.decode) {
          | Some(kept) => ({id, secret: kept}: organization)
          | None =>
            await writeJson(
              `state/organizations/${Float.toString(id)}`,
              organizationJson(id, label, secret),
            )
            ({id, secret}: organization)
          }
        | None =>
          let id = next(all)
          await writeJson(
            `state/organizations/${Float.toString(id)}`,
            organizationJson(id, label, secret),
          )
          ({id, secret}: organization)
        }
      }),
    hasOrganization: async id => (await organization(id))->Option.isSome,
    organizationSecret: async id =>
      (await organization(id))->Option.flatMap(json =>
        json->text("secret")->Option.flatMap(Envelope.Hex.decode)
      ),
    openBinding: (~organization, ~secret, ~relayed) =>
      serial(async () => {
        let id = next(await every("state/bindings/"))
        await writeJson(
          bindingAt(id),
          bindingJson({id, organization, secret, tunnel: None, address: None, relayed}),
        )
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
