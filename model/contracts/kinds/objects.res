/**
 * The `object` kind's contract, RFC vr5lw: what the blob asks, RFC vuanj, and no more, every object
 * at most 16 MiB, in the platform's own protocol. S3 is a bridge around a bucket, never this.
 */
open Subset

/** The most an object holds, in bytes: a parcel's 16 MiB, b8f35. */
let most =
  16 * 1024 * 1024

let types: array<declared> = [
  {name: "object-name", def: Record([field("name", 1, Prim(#string))]), from: "vr5lw"},
  {
    name: "object-write",
    def: Record([field("name", 1, Prim(#string)), field("content", 2, Prim(#bytes))]),
    from: "vr5lw",
  },
  {name: "object-written", def: Record([]), from: "vr5lw"},
  // A range is its first byte and how many after it; one running past the end is cut there.
  {
    name: "object-range",
    def: Record([field("start", 1, Prim(#uint53)), field("length", 2, Prim(#uint53))]),
    from: "vr5lw",
  },
  {
    name: "object-read",
    def: Record([field("name", 1, Prim(#string)), optional("range", 2, Type("object-range"))]),
    from: "vr5lw",
  },
  // The whole object's size beside what was read of it.
  {
    name: "object-content",
    def: Record([field("content", 1, Prim(#bytes)), field("size", 2, Prim(#uint53))]),
    from: "vr5lw",
  },
  // Its size, absent when no object is there.
  {name: "object-described", def: Record([optional("size", 1, Prim(#uint53))]), from: "vr5lw"},
  {name: "object-deleted", def: Record([]), from: "vr5lw"},
  // Names after `after` in byte order, at most `limit`, a thousand unless set.
  {
    name: "object-list",
    def: Record([
      field("prefix", 1, Prim(#string)),
      optional("after", 2, Prim(#string)),
      optional("limit", 3, Prim(#uint32)),
    ]),
    from: "vr5lw",
  },
  {
    name: "object-listed-one",
    def: Record([field("name", 1, Prim(#string)), field("size", 2, Prim(#uint53))]),
    from: "vr5lw",
  },
  // `next` is the name to list after, absent once none is left.
  {
    name: "object-listed",
    def: Record([
      field("objects", 1, List(Type("object-listed-one"))),
      optional("next", 2, Prim(#string)),
    ]),
    from: "vr5lw",
  },
]

/**
 * Deleting what is not there, and describing it, succeed: neither is a failure, each read seeing
 * every write before it.
 */
let interface_: interface_ = {
  name: "object",
  version: 1,
  bounds: dict{"content": most},
  from: "vr5lw",
  operations: [
    op(
      "write",
      "object-write",
      "object-written",
      [("too_large", #rejected), ("storage_full", #unavailable)],
    ),
    op("read", "object-read", "object-content", [("not_found", #rejected)]),
    op("describe", "object-name", "object-described", []),
    op("delete", "object-name", "object-deleted", []),
    op("list", "object-list", "object-listed", []),
  ],
}
