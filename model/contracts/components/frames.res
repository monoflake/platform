/**
 * A machine tablet's copies among themselves, SQLite's WAL frames from the primary, a write done
 * once a majority holds it and a handover fenced by generation, RFC vuanj.
 */
open Subset

let types: array<declared> = [
  // Frames from `from` on, at the primary's generation, and how far is done.
  {
    name: "copies-append",
    def: Record([
      field("tablet", 1, Prim(#string)),
      field("generation", 2, Prim(#uint53)),
      field("from", 3, Prim(#uint53)),
      field("frames", 4, Prim(#bytes)),
      field("done", 5, Prim(#uint53)),
    ]),
    from: "vuanj",
  },
  // How many frames a copy holds flushed, and the generation it has taken.
  {
    name: "copies-held",
    def: Record([field("held", 1, Prim(#uint53)), field("generation", 2, Prim(#uint53))]),
    from: "vuanj",
  },
  // A generation offered, one past the last, by a copy that heard nothing for a lease.
  {
    name: "copies-take",
    def: Record([field("tablet", 1, Prim(#string)), field("generation", 2, Prim(#uint53))]),
    from: "vuanj",
  },
  {
    name: "copies-fetch",
    def: Record([
      field("tablet", 1, Prim(#string)),
      field("from", 2, Prim(#uint53)),
      optional("limit", 3, Prim(#uint53)),
    ]),
    from: "vuanj",
  },
  // Frames from where they were asked, at most a part's bound, and the index past the last.
  {
    name: "copies-fetched",
    def: Record([field("frames", 1, Prim(#bytes)), field("through", 2, Prim(#uint53))]),
    from: "vuanj",
  },
]

/**
 * A generation below the copy's is stale, so an old primary gathers no majority; frames beginning
 * past what the copy holds leave a gap, which it fetches before it takes them.
 */
let interface_: interface_ = {
  name: "copies",
  version: 1,
  bounds: dict{"part": Objects.most},
  from: "vuanj",
  operations: [
    op(
      "append",
      "copies-append",
      "copies-held",
      [("stale", #rejected), ("gap", #rejected), ("too_large", #rejected)],
    ),
    op("take", "copies-take", "copies-held", [("stale", #rejected)]),
    op("fetch", "copies-fetch", "copies-fetched", [("gap", #rejected)]),
  ],
}
