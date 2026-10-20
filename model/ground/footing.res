/**
 * What a footing keeps and what it is asked to write, RFC b8f35. A footing is a database priced by
 * the row, so `check.res` asks two things of it: that what it keeps is bounded, growing with neither
 * the content its owner holds nor time, and how many rows a day each step of the bootstrap path asks
 * of the vendor's plan, `docs/scope.md`. Reads follow the caches above, and are not counted here.
 */
/**
 * How what a footing keeps grows. Only `bounded` may stand; the rest wait on a row: `bounded` by a
 * constant for each owner, however much it holds and however long; `content` with the content its
 * owner holds; `owners` with every owner there has ever been.
 */
type growth = [#bounded | #content | #owners]

type kept = {
  /** Whose footing keeps it, vr5lw. */
  of_: [#platform | #organization],
  what: string,
  from: string,
  grows: growth,
  /** What bounds it, for `bounded`. */
  bound?: string,
  /** While it is not bounded, the question naming its row. */
  open_?: string,
}

let kept: dict<kept> = dict{
  "backing": {
    of_: #organization,
    what: "a scope's stores",
    from: "b8f35",
    grows: #bounded,
    bound: "the stores a scope binds",
  },
  "journals": {
    of_: #organization,
    what: "which journal each placement writes; the journals themselves are kept in the stores",
    from: "b8f35",
    grows: #bounded,
    bound: "a row for each placement a scope writes, which the levels' product bounds",
  },
  "writers": {
    of_: #organization,
    what: "for each tablet on machines, its copies, its primary and its generation; a vendor's holds its own writer",
    from: "b8f35, vuanj",
    grows: #bounded,
    bound: "a row for each of a scope's tablets",
  },
  "bundle": {
    of_: #organization,
    what: "the organization's bundle",
    from: "v7v3w",
    grows: #bounded,
    bound: "one, holding what the organization opened, as many as its allowance lets it",
  },
  "extent": {
    of_: #organization,
    what: "which pieces each content is made of, each piece's parcel, and every parcel",
    from: "b8f35",
    grows: #bounded,
    bound: "the footing's 10 GB, about 35 million pieces, an organization's 30 TB reached before it; past either it is split",
  },
  "anchor": {
    of_: #platform,
    what: "a row for every scope there has been, the platform's footing alone",
    from: "b8f35",
    grows: #owners,
    open_: "the anchor keeps a row for every scope ever made, never removed: how many the platform's footing holds, and what comes after [D7]",
  },
}

/**
 * Rows written for one of each operation, as RFCs b8f35 and vuanj lay a write out: a tablet's
 * batch is its implementation's own, kept by it and rewound by it, so it writes no row of the
 * footing, and the extent's rows are the footing's own. A row written and later removed counts
 * twice, since a deletion is a write.
 */
type rows = {
  /** A file of one new piece: its extent's two rows, its bytes put to the stores as a journal's
   * object; then the piece's parcel written as the journal is exported. Its name and the count
   * its content is held by are the storage's tablet's. */
  smallWrite: float,
  /** A file whose content is held already: the count raised, in the storage's tablet alone. */
  duplicate: float,
  /** A MiB of a large file sealed at once: about one piece's two extent rows and a parcel's row
   * spread over the 16 pieces of a parcel. */
  largeMiB: float,
  /** An app's database commit: none, its tablet's own. */
  commit: float,
  /** A tablet a day while idle: none, its primary held by its copies hearing from it, a vendor's by
   * the vendor, vuanj. */
  idleTablet: float,
  /** A tablet on machines taken over by another primary, or a copy of it replaced: its generation
   * raised. */
  takeover: float,
}

let rows = {
  smallWrite: 3.,
  duplicate: 0.,
  largeMiB: 2.06,
  commit: 0.,
  idleTablet: 0.,
  takeover: 1.,
}

/** Rows written a day that a plan allows a whole account, `docs/lessons/`: the paid plan's included
 * 50 million a month, spread over 30 days. */
let allowed = (plan: Steps.plan) =>
  switch plan {
  | #free => 100_000.
  | #paid => 50_000_000. /. 30.
  }

/**
 * What the model assumes of the foundation platform's account at each step, until it is measured
 * [C7]: how many organizations the production platform holds, each standing on a cell of its own
 * while cells are one each; how many tablets each organization keeps -- the storage's metadata, the
 * functions', and its apps' databases.
 */
type assumed = {
  /** The production organizations at each step, the author's own until users come at step 8. */
  production: int => float,
  /** The foundation platform's own organizations: the console's dashboard's and the production platform's. */
  foundation: float,
  tablets: float,
}

let assumed = {
  production: step => step < 1 ? 0. : step < 8 ? 5. : 20.,
  foundation: 2.,
  tablets: 4.,
}
