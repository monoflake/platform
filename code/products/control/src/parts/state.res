open Records

include State_types

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

type releaseRow = {
  hash: string,
  form: string,
  size: float,
  kinds: Nullable.t<string>,
  ingress: Nullable.t<string>,
}
type deploymentRow = {
  ingress: Nullable.t<string>,
  app: float,
  binding: float,
  release: string,
  capacity: float,
  kind: Nullable.t<string>,
}

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

/** The lowest free address, stepping over held ones and materialized once as `a`. */
let unaddressed = `WITH RECURSIVE n(v) AS (SELECT 1 UNION ALL SELECT v + 1 FROM n
  WHERE v < ${Int.toString(Addresses.count)} AND '10.200.' || (v / 256) || '.' || (v % 256)
  IN (SELECT address FROM binding WHERE address IS NOT NULL)),
  a(address) AS MATERIALIZED (SELECT '10.200.' || (v / 256) || '.' || (v % 256) FROM n
  WHERE '10.200.' || (v / 256) || '.' || (v % 256)
  NOT IN (SELECT address FROM binding WHERE address IS NOT NULL))`

type addressRow = {address: Nullable.t<string>}

/** Whether the app a parameter names is held, its record kept or a deployment kept that ran. */
let appHeld = app =>
  `(EXISTS (SELECT 1 FROM app WHERE id = ${app})
  OR EXISTS (SELECT 1 FROM deployment WHERE app = ${app} AND ${ranRow}))`

/** The order a binding is given its address in, after every one given before, RFC rxmd9. */
let followingBound = "(SELECT COALESCE(MAX(bound), 0) + 1 FROM binding)"

let firstOf = async (database, sql, values) =>
  (await database->Stores.prepare(sql)->Stores.bind(values)->Stores.first)->Nullable.toOption

let bindingAt = (database, id): promise<option<bindingRow>> =>
  firstOf(database, `SELECT ${bindingColumns} FROM binding WHERE id = ?`, [Number(id)])

let deploymentAt = async (database, app) =>
  (
    await firstOf(
      database,
      "SELECT app, binding, release, capacity, kind, ingress FROM deployment WHERE app = ?",
      [Number(app)],
    )
  )->Option.flatMap((row: deploymentRow) => {
    let {app, binding, release, capacity} = row
    let ingress = row.ingress->Nullable.toOption->Option.map(Ingress.ofText)
    switch row.kind->Nullable.toOption->Option.map(kindOf) {
    | None => Some(({app, binding, release, capacity, ?ingress, kind: None}: deployment))
    | Some(Some(kind)) =>
      Some(({app, binding, release, capacity, ?ingress, kind: Some(kind)}: deployment))
    | Some(None) => None
    }
  })

type domainRow = {app: float}

let domainAt = async (database, domain) =>
  (
    await firstOf(database, "SELECT app FROM domain WHERE domain = ?", [Text(domain)])
  )->Option.map((row: domainRow) => row.app)

let mountAt = async (database, ~organization, ~scope) =>
  (
    await firstOf(
      database,
      "SELECT app FROM scope WHERE organization = ? AND scope = ?",
      [Number(organization), Text(scope)],
    )
  )->Option.map((row: domainRow) => row.app)

let readsOfDatabase = (database): reads => {
  domain: name => domainAt(database, name),
  mount: (~organization, ~scope) => mountAt(database, ~organization, ~scope),
  binding: async id =>
    (await bindingAt(database, id))->Option.map((row): reached => {
      address: row.address->Nullable.toOption,
      origin: row.origin->Nullable.toOption,
      bound: row.bound->Nullable.toOption,
    }),
  deployment: app => deploymentAt(database, app),
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
    origin: row.origin->Nullable.toOption,
    relayed: row.relayed != 0.,
    bound: row.bound->Nullable.toOption,
  }
  let bindingFrom = async (sql, values) =>
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
    binding: async id =>
      switch await bindingAt(database, id) {
      | Some(row) => Some(await bindingOf(row))
      | None => None
      },
    storage: organization =>
      bindingFrom(
        `SELECT ${bindingColumns} FROM binding
        WHERE organization = ? AND relayed = 0 AND bound IS NOT NULL AND origin IS NULL
        ORDER BY bound LIMIT 1`,
        [Number(organization)],
      ),
    addressedAt: address =>
      bindingFrom(`SELECT ${bindingColumns} FROM binding WHERE address = ?`, [Text(address)]),
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
    domain: name => domainAt(database, name),
    putRelease: release =>
      run(
        "INSERT INTO release (hash, form, size, kinds, ingress) VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (hash) DO NOTHING",
        [
          Text(release.hash),
          Text(formName(release.form)),
          Number(release.size),
          release.kinds->Option.mapOr(Stores.Null, kinds => Text(kindsText(kinds))),
          release.ingress->Option.mapOr(Stores.Null, i => Text(Ingress.toText(i))),
        ],
      ),
    release: async hash =>
      (
        await first(
          "SELECT hash, form, size, kinds, ingress FROM release WHERE hash = ?",
          [Text(hash)],
        )
      )->Option.flatMap((row: releaseRow) => {
        let ingress = row.ingress->Nullable.toOption->Option.map(Ingress.ofText)
        switch (formOf(row.form), row.kinds->Nullable.toOption) {
        | (Some(form), None) =>
          Some(({hash: row.hash, form, size: row.size, ?ingress, kinds: None}: release))
        | (Some(form), Some(text)) =>
          kindsOfText(text)->Option.map((kinds): release => {
            hash: row.hash,
            form,
            size: row.size,
            ?ingress,
            kinds: Some(kinds),
          })
        | (None, _) => None
        }
      }),
    // Written only where the app is held, so a forgotten app's deploy never lands.
    deploy: async d => {
      let deployed = statement(
        `INSERT INTO deployment (app, binding, release, capacity, kind, ingress) SELECT ?1, ?2, ?3, ?4, ?5, ?6
        WHERE ${appHeld("?1")} ON CONFLICT (app) DO UPDATE SET binding = excluded.binding,
        release = excluded.release, capacity = excluded.capacity, kind = excluded.kind, ingress = excluded.ingress`,
        [
          Number(d.app),
          Number(d.binding),
          Text(d.release),
          Number(d.capacity),
          d.kind->Option.mapOr(Stores.Null, kind => Text(kindName(kind))),
          d.ingress->Option.mapOr(Stores.Null, i => Text(Ingress.toText(i))),
        ],
      )
      let domains = Ingress.domains(d.ingress)
      let cleared = statement("DELETE FROM domain WHERE app = ?", [Number(d.app)])
      let added =
        domains->Array.map(domain =>
          statement(
            "INSERT INTO domain (domain, app) SELECT ?1, ?2 WHERE EXISTS (SELECT 1 FROM deployment WHERE app = ?2)",
            [Text(domain), Number(d.app)],
          )
        )
      let scopes = Ingress.scopes(d.ingress)
      let unmounted = statement("DELETE FROM scope WHERE app = ?", [Number(d.app)])
      let mounted =
        scopes->Array.map(scope =>
          statement(
            "INSERT INTO scope (organization, scope, app) SELECT organization, ?1, ?2 FROM binding WHERE id = ?3 AND EXISTS (SELECT 1 FROM deployment WHERE app = ?2)",
            [Text(scope), Number(d.app), Number(d.binding)],
          )
        )
      switch await database->Stores.batch([deployed, cleared, unmounted, ...added, ...mounted]) {
      | () => ()
      | exception JsExn(e) =>
        let other = holder => holder->Option.mapOr(false, app => app != d.app)
        let holders = await Promise.all(domains->Array.map(domain => domainAt(database, domain)))
        switch domains->Array.findWithIndex((_, i) => other(holders->Array.getUnsafe(i))) {
        | Some(domain) => throw(DomainHeld(domain))
        | None =>
          switch await bindingAt(database, d.binding) {
          | None => throw(JsExn(e))
          | Some({organization}) =>
            let holders = await Promise.all(
              scopes->Array.map(scope => mountAt(database, ~organization, ~scope)),
            )
            switch scopes->Array.findWithIndex((_, i) => other(holders->Array.getUnsafe(i))) {
            | Some(scope) => throw(Ingress.ScopeHeld(scope))
            | None => throw(JsExn(e))
            }
          }
        }
      }
    },
    deployment: app => deploymentAt(database, app),
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

let ofObjects = State_objects.ofObjects
