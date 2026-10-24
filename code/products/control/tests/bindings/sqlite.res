/*** node's SQLite in memory standing in for D1, called as `Stores` calls D1. */
type sqlite
@module("node:sqlite") @new external openSqlite: string => sqlite = "DatabaseSync"
@send external exec: (sqlite, string) => unit = "exec"

let asDatabase: sqlite => Stores.database = %raw(`db => ({
  prepare: sql => ({
    bind: (...values) => {
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
let database = () => {
  let db = openSqlite(":memory:")
  let migrations = Node.fromRoot("code/products/control/migrations")
  Node.list(migrations, {recursive: false})
  ->Array.filter(name => name->String.endsWith(".sql"))
  ->Array.toSorted(String.compare)
  ->Array.forEach(name => db->exec(Node.readText(Node.join([migrations, name]))))
  asDatabase(db)
}
