/**
 * The `database` kind's contract, RFCs zn3u5 and vr5lw: SQLite's dialect, one statement or a batch
 * atomic together, each with its parameters, answered with each one's rows. No interactive
 * transaction. A database's limits are its driver's to declare, vr5lw [C23].
 */
open Subset

let types: array<declared> = [
  // A value of SQLite's, its case in `kind` and its payload in `value`, as vr5lw writes it.
  {
    name: "database-value",
    def: Union({
      tag: "kind",
      cases: [
        {name: "null", code: 1, fields: []},
        {name: "integer", code: 2, fields: [field("value", 1, Prim(#int64))]},
        {name: "real", code: 3, fields: [field("value", 1, Prim(#float64))]},
        {name: "text", code: 4, fields: [field("value", 1, Prim(#string))]},
        {name: "bytes", code: 5, fields: [field("value", 1, Prim(#bytes))]},
      ],
    }),
    from: "vr5lw",
  },
  {
    name: "database-statement",
    def: Record([
      field("sql", 1, Prim(#string)),
      optional("parameters", 2, List(Type("database-value"))),
    ]),
    from: "zn3u5",
  },
  {
    name: "database-execute",
    def: Record([field("statements", 1, List(Type("database-statement")))]),
    from: "zn3u5",
  },
  // A statement's rows, each its values in its columns' order, and how many rows it changed.
  {
    name: "database-result",
    def: Record([
      field("columns", 1, List(Prim(#string))),
      field("rows", 2, List(List(Type("database-value")))),
      field("changed", 3, Prim(#uint53)),
    ]),
    from: "zn3u5",
  },
  {
    name: "database-executed",
    def: Record([field("results", 1, List(Type("database-result")))]),
    from: "zn3u5",
  },
]

/** A batch that fails changes nothing, zn3u5; `index` of the failing statement is in the message. */
let interface_: interface_ = {
  name: "database",
  version: 1,
  from: "zn3u5, vr5lw",
  operations: [
    op(
      "execute",
      "database-execute",
      "database-executed",
      [
        ("invalid", #rejected),
        ("constraint", #rejected),
        ("beyond_limit", #rejected),
        ("busy", #unavailable),
      ],
    ),
  ],
}
