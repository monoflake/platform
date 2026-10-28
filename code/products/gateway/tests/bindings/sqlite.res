module Stores = ControlOrganization.Stores

/*** node's SQLite in memory standing in for D1, called as `Stores` calls D1. */
type sqlite
@module("node:sqlite") @new external openSqlite: string => sqlite = "DatabaseSync"
@send external exec: (sqlite, string) => unit = "exec"

type planRow = {id: int, parent: int, detail: string}
type plan = {sql: string, rows: array<planRow>}

let asDatabase: (sqlite, ~plans: array<plan>=?) => Stores.database = %raw(`(db, plans) => ({
  batch: async statements => {
    db.exec('BEGIN')
    try {
      for (const statement of statements) await statement.run()
      db.exec('COMMIT')
    } catch (error) {
      db.exec('ROLLBACK')
      throw error
    }
  },
  prepare: sql => ({
    bind: (...values) => {
      if (plans) plans.push({sql, rows: db.prepare("EXPLAIN QUERY PLAN " + sql).all(...values)})
      const statement = db.prepare(sql)
      return {
        first: async () => statement.get(...values) ?? null,
        run: async () => { statement.run(...values) },
      }
    },
  }),
})`)

/** A database whose statements beginning with `prefix` throw as they are run. */
let refusing: (Stores.database, string) => Stores.database = %raw(`(db, prefix) => ({
  batch: statements => db.batch(statements),
  prepare: sql => sql.startsWith(prefix)
    ? {
        bind: () => {
          const refused = async () => { throw new Error("refused " + prefix) }
          return { first: refused, run: refused }
        },
      }
    : db.prepare(sql),
})`)

/** A database in memory with the control's migrations applied in order. */
let database = (~plans=?, ()) => {
  let db = openSqlite(":memory:")
  let migrations = Node.fromRoot("code/products/control/migrations")
  Node.list(migrations, {recursive: false})
  ->Array.filter(name => name->String.endsWith(".sql"))
  ->Array.toSorted(String.compare)
  ->Array.forEach(name => db->exec(Node.readText(Node.join([migrations, name]))))
  asDatabase(db, ~plans?)
}
