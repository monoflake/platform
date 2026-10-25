/**
 * The `database` kind's contract, SQLite's dialect in statements or atomic batches, integers within
 * 2^53 and 30 days of rewind, RFCs zn3u5 and vr5lw.
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
        {name: "integer", code: 2, fields: [field("value", 1, Prim(#int53))]},
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
  // A minute of the last 30 days to rewind to, in milliseconds; what is answered is the moment just
  // before, which a rewind to undoes, as each implementation keeps every minute of 30 days.
  {name: "database-rewind", def: Record([field("to", 1, Prim(#uint53))]), from: "zn3u5, vr5lw"},
  {
    name: "database-rewound",
    def: Record([field("before", 1, Prim(#uint53))]),
    from: "zn3u5, vr5lw",
  },
  // `behind` where read from fewer copies than a majority, which may lack a write done, vuanj.
  {
    name: "database-executed",
    def: Record([
      field("results", 1, List(Type("database-result"))),
      optional("behind", 2, Prim(#bool)),
    ]),
    from: "zn3u5, vuanj",
  },
]

/**
 * A batch that fails changes nothing, zn3u5. A database with fewer copies alive than a majority is
 * read-only and answers reads `behind`, vuanj.
 */
let interface_: interface_ = {
  name: "database",
  version: 3,
  declared: ["statement"],
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
        ("beyond_range", #rejected),
        ("storage_full", #unavailable),
        ("read_only", #unavailable),
      ],
      ~callers=[#organization, #component],
    ),
    op(
      "rewind",
      "database-rewind",
      "database-rewound",
      [("beyond_window", #rejected)],
      ~callers=[#organization, #component],
    ),
  ],
}
