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
  // A tier of what is kept past 30 days, a snapshot every so often kept until so old, as restic's
  // buckets.
  {
    name: "database-retention",
    def: Record([field("every", 1, Prim(#uint53)), field("keep", 2, Prim(#uint53))]),
    from: "zn3u5",
  },
  // A database bound to one app, its read copies, copies, snapshots and tiers, each one or none
  // unless set, vuanj and 13ixj.
  {
    name: "database",
    def: Record([
      field("kind", 1, Type("database-kind")),
      field("app", 2, Id("app")),
      optional("read_copies", 3, Prim(#bool)),
      optional("snapshot_copies", 4, Prim(#uint32)),
      optional("placement", 5, Type("placement")),
      field("levels", 6, Type("database-levels")),
      optional("retention", 7, List(Type("database-retention"))),
      optional("copies", 8, Prim(#uint32)),
    ]),
    from: "zn3u5, vuanj",
  },
  // The database product's section of a bundle, each database by its id with its app and copies,
  // vuanj.
  {
    name: "bundle-database",
    def: Record([field("databases", 1, Map(Type("database")))]),
    from: "vuanj",
  },
]

let contents: array<content> = [
  {half: #organization, kind: "database", version: 2, content: "database"},
]

/**
 * A database's copies, 1 to 5, a write done once a majority of those configured hold it, RFC vuanj.
 * Fewer alive is read-only until fewer are configured.
 */
let copiesMost = 5

/** How many copies hold a write before it is done, 1 of 1, 2 of 2, 2 of 3, 3 of 4 and 3 of 5. */
let majority = copies => copies / 2 + 1

/** The copies an owner may configure to release the lock, those `alive` are a majority of. */
let releasing = alive =>
  Array.fromInitializer(~length=copiesMost, i => i + 1)->Array.filter(n =>
    n >= alive && majority(n) <= alive
  )

let hour = 3_600_000.
let day = 24. *. hour

/**
 * What a database's tiers are held to, none unless set, at most a year back and one snapshot an
 * hour, each sparser and older. Its control refuses any other.
 */
let retentionMost =
  365. *. day
let retentionFinest = hour

/**
 * The tiers a database is given when its owner turns them on, and changes as it likes within the
 * bounds.
 */
let retentionPreset = [(day, 90. *. day), (7. *. day, 180. *. day), (30. *. day, 365. *. day)]
