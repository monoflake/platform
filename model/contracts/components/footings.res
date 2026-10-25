/**
 * An organization's footing, its records read and written by kind, a change applied whole on its
 * conditions, the signed bundle, and leases by the footing's clock, RFC n8jq5.
 */
open Subset

let types: array<declared> = [
  // A row as its footing keeps it, the shell `Subset.shell` writes, its content the kind's record
  // in CBOR at its version.
  {
    name: "footing-row",
    def: Record([
      field("kind", 1, Prim(#string)),
      field("id", 2, Prim(#uint32)),
      field("generation", 3, Prim(#uint53)),
      field("version", 4, Prim(#uint32)),
      optional("content", 5, Prim(#bytes)),
    ]),
    from: "n8jq5, v7v3w",
  },
  // A kind's rows, one by its id, or those whose unique key begins with the fields given, each a
  // value in CBOR by its field's name; a page after the id a page before ended at.
  {
    name: "footing-read",
    def: Record([
      field("kind", 1, Prim(#string)),
      optional("id", 2, Prim(#uint32)),
      optional("key", 3, Map(Prim(#bytes))),
      optional("after", 4, Prim(#uint32)),
      optional("limit", 5, Prim(#uint53)),
    ]),
    from: "n8jq5",
  },
  // `next` is where the following page begins, absent on the last.
  {
    name: "footing-rows",
    def: Record([field("rows", 1, List(Type("footing-row"))), optional("next", 2, Prim(#uint32))]),
    from: "n8jq5",
  },
  // A row written on its condition, new where it names no id and at the generation read where it
  // does; one with an id and no content is deleted.
  {
    name: "footing-change-row",
    def: Record([
      field("kind", 1, Prim(#string)),
      optional("id", 2, Prim(#uint32)),
      optional("at", 3, Prim(#uint53)),
      field("version", 4, Prim(#uint32)),
      optional("content", 5, Prim(#bytes)),
    ]),
    from: "n8jq5, v7v3w",
  },
  // A change, applied all or none; its generation reverts to `reverts` where it names one, v7v3w.
  {
    name: "footing-write",
    def: Record([
      field("rows", 1, List(Type("footing-change-row"))),
      optional("reverts", 2, Prim(#uint53)),
    ]),
    from: "n8jq5, v7v3w",
  },
  // The generation the change made, and each row's id in the order written.
  {
    name: "footing-written",
    def: Record([field("generation", 1, Prim(#uint53)), field("ids", 2, List(Prim(#uint32)))]),
    from: "n8jq5",
  },
  // The newest bundle, no older than the generation a reader last read.
  {
    name: "footing-bundle-of",
    def: Record([optional("at_least", 1, Prim(#uint53))]),
    from: "n8jq5, v7v3w",
  },
  // The bundle as its signer signed it, whole, since its signature covers every section.
  {
    name: "footing-bundle",
    def: Record([field("generation", 1, Prim(#uint53)), field("bundle", 2, Prim(#bytes))]),
    from: "n8jq5, b8f35",
  },
  {
    name: "lease-action",
    def: Enum({choices: codes(["take", "renew", "release"]), ordered: false}),
    from: "n8jq5",
  },
  // A lease by name, for so many seconds of the footing's clock; its holder is the caller's
  // instance, by its key's `kid`, 8yl4b.
  {
    name: "footing-lease",
    def: Record([
      field("name", 1, Prim(#string)),
      field("action", 2, Type("lease-action")),
      optional("seconds", 3, Prim(#uint53)),
    ]),
    from: "n8jq5, b8f35",
  },
  // When the lease ends by the footing's clock, absent once released.
  {
    name: "footing-leased",
    def: Record([optional("until", 1, Prim(#uint53))]),
    from: "n8jq5, b8f35",
  },
]

/**
 * A call is signed by its caller's instance key and judged by the model, a write by the kind's
 * writers and the rest by the caller's edges to the footing, jy0s5.
 */
let interface_: interface_ = {
  name: "footing",
  version: 1,
  from: "n8jq5",
  operations: [
    op("read", "footing-read", "footing-rows", [("no_kind", #rejected)], ~callers=[#component]),
    op(
      "write",
      "footing-write",
      "footing-written",
      [("stale", #rejected), ("no_kind", #rejected), ("too_large", #rejected)],
      ~callers=[#component],
    ),
    op(
      "bundle",
      "footing-bundle-of",
      "footing-bundle",
      [("behind", #unavailable)],
      ~callers=[#component],
    ),
    op("lease", "footing-lease", "footing-leased", [("held", #rejected)], ~callers=[#component]),
  ],
}
