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
