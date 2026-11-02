module C = Envelope.Contracts

type t = {database: Stores.database, now: unit => float}
type row = {grant: string, verifier: string, expires: float, revoked: int, policy: string}
type staging = {size: float, expires: float, token: string}
type stagedRow = {grant: string, digest: string}
type fetchable = {token: string, expires: float, revoked: int, lapses: float}
type grantId = {grant: string}
type appId = {app: float}
type readiness = {ready: int}
type head = {app: float, digest: string, version: float, candidate: string, locked: string}

let query = (s, sql, values) => s.database->Stores.prepare(sql)->Stores.bind(values)
let first = async (s, sql, values) => (await query(s, sql, values)->Stores.first)->Nullable.toOption
let run = (s, sql, values) => query(s, sql, values)->Stores.run

let get = (s, id): promise<option<row>> =>
  first(
    s,
    "SELECT grant, verifier, expires, revoked, policy FROM deployment_grant WHERE grant = ?",
    [Text(id)],
  )

let live = (s, row: row) => row.revoked == 0 && row.expires > s.now()

let policy = (row: row) => C.DeploymentGrantPolicy.fromJson(JSON.parseOrThrow(row.policy))

let insert = (s, row: row, ~app) =>
  run(
    s,
    "INSERT INTO deployment_grant (grant, verifier, expires, revoked, policy, app) VALUES (?, ?, ?, 0, ?, ?)",
    [
      Text(row.grant),
      Text(row.verifier),
      Number(row.expires),
      Text(row.policy),
      app->Option.mapOr(Stores.Null, app => Number(app)),
    ],
  )

let revoke = async (s, id) => {
  let found: option<grantId> = await first(
    s,
    "UPDATE deployment_grant SET revoked = 1 WHERE grant = ? RETURNING grant",
    [Text(id)],
  )
  found->Option.isSome
}

let head = (s, app): promise<option<head>> =>
  first(
    s,
    "SELECT app, digest, version, candidate, locked FROM grant_head WHERE app = ?",
    [Number(app)],
  )

let initialize = (s, app, digest, candidate) =>
  run(
    s,
    "INSERT OR IGNORE INTO grant_head (app, digest, candidate) VALUES (?, ?, ?)",
    [Number(app), Text(digest), Text(candidate)],
  )

let staged = (s, grant, digest): promise<option<staging>> =>
  first(
    s,
    "SELECT size, expires, token FROM grant_staging WHERE grant = ? AND digest = ?",
    [Text(grant), Text(digest)],
  )

// A second upload of one digest keeps the token a driver may already be fetching with.
let stage = async (s, grant, digest, size, expires, token) => {
  let found: option<grantId> = await first(
    s,
    "INSERT INTO grant_staging (grant, digest, size, expires, token) SELECT grant, ?, ?, ?, ? FROM deployment_grant WHERE grant = ? AND revoked = 0 AND expires > ? AND (SELECT COUNT(*) FROM grant_staging WHERE grant = ? AND digest != ? AND expires > ?) < 4 ON CONFLICT (grant, digest) DO UPDATE SET size = excluded.size, expires = excluded.expires RETURNING grant",
    [
      Text(digest),
      Number(size),
      Number(expires),
      Text(token),
      Text(grant),
      Number(s.now()),
      Text(grant),
      Text(digest),
      Number(s.now()),
    ],
  )
  found->Option.isSome
}

let unstage = (s, grant, digest) =>
  run(s, "DELETE FROM grant_staging WHERE grant = ? AND digest = ?", [Text(grant), Text(digest)])

let unnamed = "NOT EXISTS (SELECT 1 FROM grant_head WHERE locked != '' AND instr(locked, grant_staging.digest) > 0)"

let expired = async (s, limit): array<stagedRow> => {
  let found = await query(
    s,
    `SELECT grant, digest FROM grant_staging WHERE expires <= ? AND ${unnamed} ORDER BY expires LIMIT ?`,
    [Number(s.now()), Number(limit)],
  )->Stores.all
  found.Stores.results
}

let stagedBy = async (s, grant): array<stagedRow> => {
  let found = await query(
    s,
    `SELECT grant, digest FROM grant_staging WHERE grant = ? AND ${unnamed}`,
    [Text(grant)],
  )->Stores.all
  found.Stores.results
}

let stagedFor = async (s, app): array<stagedRow> => {
  let found = await query(
    s,
    "SELECT grant_staging.grant AS grant, grant_staging.digest AS digest FROM deployment_grant JOIN grant_staging ON grant_staging.grant = deployment_grant.grant WHERE deployment_grant.app = ?",
    [Number(app)],
  )->Stores.all
  found.Stores.results
}

let fetchable = (s, grant, digest): promise<option<fetchable>> =>
  first(
    s,
    "SELECT grant_staging.token AS token, grant_staging.expires AS expires, deployment_grant.revoked AS revoked, deployment_grant.expires AS lapses FROM grant_staging JOIN deployment_grant ON deployment_grant.grant = grant_staging.grant WHERE grant_staging.grant = ? AND grant_staging.digest = ?",
    [Text(grant), Text(digest)],
  )

let lock = async (s, app, expected, token) => {
  let found: option<appId> = await first(
    s,
    "UPDATE grant_head SET locked = ? WHERE app = ? AND version = ? AND locked = '' RETURNING app",
    [Text(token), Number(app), Number(expected)],
  )
  found->Option.isSome
}

let unlock = (s, app, token) =>
  run(
    s,
    "UPDATE grant_head SET locked = '' WHERE app = ? AND locked = ?",
    [Number(app), Text(token)],
  )

let commit = async (s, ~app, ~expected, ~token, ~grant, ~digest, ~candidate) => {
  let found: option<appId> = await first(
    s,
    "UPDATE grant_head SET digest = ?, candidate = ?, grant = ?, version = version + 1, locked = '' WHERE app = ? AND version = ? AND locked = ? RETURNING app",
    [Text(digest), Text(candidate), Text(grant), Number(app), Number(expected), Text(token)],
  )
  found->Option.isSome
}

// An operator's effect, recorded with no audit row since the audit names a grant.
let adopt = async (s, ~app, ~expected, ~token, ~digest, ~candidate) => {
  let found: option<appId> = await first(
    s,
    "UPDATE grant_head SET digest = ?, candidate = ?, grant = NULL, version = version + 1, locked = '' WHERE app = ? AND version = ? AND locked = ? RETURNING app",
    [Text(digest), Text(candidate), Number(app), Number(expected), Text(token)],
  )
  found->Option.isSome
}

// An operator's version bump, written before its driver call and keeping its intent.
let bump = async (s, ~app, ~token, ~candidate) => {
  let found: option<appId> = await first(
    s,
    "UPDATE grant_head SET digest = COALESCE((SELECT release FROM deployment WHERE app = ?), digest), candidate = ?, grant = NULL, version = version + 1 WHERE app = ? AND locked = ? RETURNING app",
    [Number(app), Text(candidate), Number(app), Text(token)],
  )
  found->Option.isSome
}

let releaseLock = async (s, app, token) => {
  switch await unlock(s, app, token) {
  | () => ()
  | exception JsExn(_) =>
    switch await unlock(s, app, token) {
    | () => ()
    | exception JsExn(_) => ()
    }
  }
}

type countRow = {count: int}

let room = async (s, grant, digest) => {
  let found: option<countRow> = await first(
    s,
    "SELECT COUNT(*) AS count FROM grant_staging WHERE grant = ? AND digest != ? AND expires > ?",
    [Text(grant), Text(digest), Number(s.now())],
  )
  found->Option.mapOr(false, row => row.count < 4)
}

let readable = async s => {
  let found: option<readiness> = await first(s, "SELECT 1 AS ready", [])
  found->Option.isSome
}

let claim = async (s, app, previous, next) => {
  let found: option<appId> = await first(
    s,
    "UPDATE grant_head SET locked = ? WHERE app = ? AND locked = ? RETURNING app",
    [Text(next), Number(app), Text(previous)],
  )
  found->Option.isSome
}
