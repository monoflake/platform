/** The database product's record, RFC zn3u5. */
open Subset

let types: array<declared> = [
  // `transactional` alone in v0; an analytical kind is chosen later, zn3u5.
  {
    name: "database-kind",
    def: Enum({choices: codes(["transactional"]), ordered: false}),
    from: "zn3u5",
  },
  // What the compute its writer runs on must be, vuanj.
  {
    name: "database-levels",
    def: Record([
      field("availability", 1, Type("availability")),
      field("custody", 2, Type("custody")),
    ]),
    from: "zn3u5, vuanj",
  },
  // Bound to one app as it is made, never another after; read copies off unless set; its log's
  // archive and snapshots one copy unless asked, placed as a bucket is, 13ixj.
  {
    name: "database",
    def: Record([
      field("kind", 1, Type("database-kind")),
      field("app", 2, Id("app")),
      optional("replicas", 3, Prim(#bool)),
      optional("copies", 4, Prim(#uint32)),
      optional("placement", 5, Type("placement")),
      field("levels", 6, Type("database-levels")),
    ]),
    from: "zn3u5",
  },
]

let contents: array<content> = [{kind: "database", version: 1, content: "database"}]
