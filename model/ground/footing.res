/**
 * What a footing keeps and is asked to write, RFC b8f35, held bounded and counted in rows a day
 * against each step's plan, `docs/scope.md`.
 */
/**
 * How what a footing keeps grows, `bounded` per owner, with `content` or with `owners`. Only
 * `bounded` may stand.
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

let own: dict<kept> = dict{
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
}

/** What every footing keeps, with what the platform half keeps given beside, RFC 8lkuv. */
let kept: dict<kept> = Dict.fromArray(
  Array.concat(own->Dict.toArray, Fill.part("kept")->Option.getOr(Dict.make())->Dict.toArray),
)

/**
 * Rows written for one of each operation as RFCs b8f35 and vuanj lay a write out, a deletion
 * counted as a write.
 */
type rows = {
  /**
   * A file of one new piece, its extent's two rows and then its parcel's row as the journal is
   * exported.
   */
  smallWrite: float,
  /** A file whose content is held already, the count raised in the storage's tablet alone. */
  duplicate: float,
  /**
   * A MiB of a large file sealed at once, about a piece's two extent rows and a sixteenth of a
   * parcel's row.
   */
  largeMiB: float,
  /** An app's database commit, none, its tablet's own. */
  commit: float,
  /** A tablet a day while idle, none, its primary held by its copies or its vendor, vuanj. */
  idleTablet: float,
  /** A tablet on machines taken over or a copy replaced, its generation raised. */
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

/**
 * Rows written a day that a plan allows a whole account, the paid plan's 50 million a month over 30
 * days, `docs/lessons/`.
 */
let allowed = (plan: Steps.plan) =>
  switch plan {
  | #free => 100_000.
  | #paid => 50_000_000. /. 30.
  }

/**
 * What the model assumes of one organization's tablets until it is measured [C7]. The organizations
 * at each step are the hosted platform's, RFC 8lkuv.
 */
type assumed = {tablets: float}

let assumed = {tablets: 4.}
