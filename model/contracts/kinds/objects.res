/**
 * The `object` kind's contract, what the blob asks and no more in the platform's own protocol, RFC
 * vr5lw. S3 is a bridge around a bucket.
 */
open Subset

/** The most an object holds in bytes, a parcel's 16 MiB, b8f35. */
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

/** Deleting or describing what is not there succeeds, and each read sees every write before it. */
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
      ~callers=[#organization, #component],
    ),
    op(
      "read",
      "object-read",
      "object-content",
      [("not_found", #rejected)],
      ~callers=[#organization, #component],
    ),
    op("describe", "object-name", "object-described", [], ~callers=[#organization, #component]),
    op("delete", "object-name", "object-deleted", [], ~callers=[#organization, #component]),
    op("list", "object-list", "object-listed", [], ~callers=[#organization, #component]),
  ],
}
