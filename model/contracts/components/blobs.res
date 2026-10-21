/**
 * The blob's interface, a product's, RFCs vuanj and b8f35: bytes in a scope by the hash of their
 * content, each product's in a space of its own. Content of any size is put by an upload, appended
 * to in order a part at a time and resumed from what is durable, and read by range, a part at most
 * a call; one of a part or less is put whole. Beneath, the blob cuts, names, seals and places it,
 * `layout*`, `keys*` and `placement*`. The components' interfaces are named for what they carry, in
 * the plural, as the products' are.
 */
open Subset

let types: array<declared> = [
  // Whose references count a hash, so no product deletes what another holds, vuanj.
  {
    name: "blob-space",
    def: Enum({
      choices: [
        {name: "storage", code: 1},
        {name: "compute", code: 2},
        {name: "database", code: 3},
      ],
      ordered: false,
    }),
    from: "vuanj",
  },
  {
    name: "blob-put",
    def: Record([
      field("space", 1, Type("blob-space")),
      field("placement", 2, Type("placement")),
      field("content", 3, Prim(#bytes)),
    ]),
    from: "vuanj",
  },
  // A content's hash, keyed by its scope's salt, and its size.
  {
    name: "blob-stored",
    def: Record([field("hash", 1, Prim(#hash)), field("size", 2, Prim(#uint53))]),
    from: "vuanj, b8f35",
  },
  // An upload's size, where it is known, is held to at its finish.
  {
    name: "blob-upload-begin",
    def: Record([
      field("space", 1, Type("blob-space")),
      field("placement", 2, Type("placement")),
      optional("size", 3, Prim(#uint53)),
    ]),
    from: "vuanj",
  },
  // An upload, by 32 random bytes, and the most one append carries.
  {
    name: "blob-upload",
    def: Record([field("upload", 1, Prim(#hash)), field("part", 2, Prim(#uint53))]),
    from: "vuanj",
  },
  // A part, appended where what was received ends.
  {
    name: "blob-upload-append",
    def: Record([
      field("upload", 1, Prim(#hash)),
      field("offset", 2, Prim(#uint53)),
      field("content", 3, Prim(#bytes)),
    ]),
    from: "vuanj",
  },
  {
    name: "blob-upload-name",
    def: Record([field("upload", 1, Prim(#hash))]),
    from: "vuanj",
  },
  // How much was received, and how much is durable: to the end of the last whole piece, sealed and
  // named, from where a dropped upload is resumed.
  {
    name: "blob-upload-state",
    def: Record([field("received", 1, Prim(#uint53)), field("durable", 2, Prim(#uint53))]),
    from: "vuanj",
  },
  {name: "blob-upload-aborted", def: Record([]), from: "vuanj"},
  {
    name: "blob-get",
    def: Record([
      field("space", 1, Type("blob-space")),
      field("hash", 2, Prim(#hash)),
      optional("range", 3, Type("object-range")),
    ]),
    from: "vuanj",
  },
  // What was read, a part at most, and the whole content's size.
  {
    name: "blob-content",
    def: Record([field("content", 1, Prim(#bytes)), field("size", 2, Prim(#uint53))]),
    from: "vuanj",
  },
  {
    name: "blob-name",
    def: Record([field("space", 1, Type("blob-space")), field("hash", 2, Prim(#hash))]),
    from: "vuanj",
  },
  // Its size, when it was put, in milliseconds, the placement it has, and the one it is moving to
  // while a place moves it; all absent when nothing is there.
  {
    name: "blob-described",
    def: Record([
      optional("size", 1, Prim(#uint53)),
      optional("put", 2, Prim(#uint53)),
      optional("placement", 3, Type("placement")),
      optional("moving", 4, Type("placement")),
    ]),
    from: "vuanj",
  },
  {
    name: "blob-place",
    def: Record([
      field("space", 1, Type("blob-space")),
      field("hash", 2, Prim(#hash)),
      field("placement", 3, Type("placement")),
    ]),
    from: "vuanj",
  },
  {name: "blob-placed", def: Record([]), from: "vuanj"},
  // A key's version retired: every parcel it sealed sealed again under the newest, b8f35.
  {name: "blob-rekey", def: Record([field("from", 1, Prim(#uint32))]), from: "b8f35"},
  // A task, by 32 random bytes, answered at once and told by `task`, RFC 49qyg.
  {name: "blob-task", def: Record([field("task", 1, Prim(#hash))]), from: "b8f35, 49qyg"},
  // How a task stands: running, done, or failed as an outcome of 49qyg's and its reason.
  {
    name: "blob-task-state",
    def: Union({
      tag: "name",
      cases: [
        {name: "running", code: 1, fields: []},
        {name: "succeeded", code: 2, fields: []},
        {
          name: "failed",
          code: 3,
          fields: [field("failure", 1, Type("failure")), field("reason", 2, Prim(#string))],
        },
      ],
    }),
    from: "b8f35, 49qyg",
  },
  {
    name: "blob-task-of",
    def: Record([field("state", 1, Type("blob-task-state"))]),
    from: "b8f35, 49qyg",
  },
  {name: "blob-deleted", def: Record([]), from: "vuanj"},
  // Hashes after `after`, in byte order, at most `limit`, a thousand unless set: for a sweep alone.
  {
    name: "blob-list",
    def: Record([
      field("space", 1, Type("blob-space")),
      optional("after", 2, Prim(#hash)),
      optional("limit", 3, Prim(#uint32)),
    ]),
    from: "vuanj",
  },
  {
    name: "blob-entry",
    def: Record([field("hash", 1, Prim(#hash)), field("put", 2, Prim(#uint53))]),
    from: "vuanj",
  },
  // `next` is where the following page begins, absent on the last.
  {
    name: "blob-listed",
    def: Record([field("entries", 1, List(Type("blob-entry"))), optional("next", 2, Prim(#hash))]),
    from: "vuanj",
  },
]

/** What every write meets: no stores of its scope meeting its placement, and none with room. */
let onWrite = [("unplaceable", #rejected), ("storage_full", #unavailable)]

/**
 * Deleting what is not there, and describing it, succeed, as the object kind's do. A placement is
 * set stricter or looser as the storage asks, the strictest of what names a content its to keep. A
 * rekey names a version older than the newest, else it is not retiring. An upload's
 * placement is asked of its stores as it begins; what is left of a part past the last whole piece
 * is written only by the next, or by the finish. An upload left a day expires, the sweep's grace,
 * and is then not found.
 */
let interface_: interface_ = {
  name: "blob",
  version: 2,
  bounds: dict{"part": Objects.most},
  from: "vuanj, b8f35",
  operations: [
    op("put", "blob-put", "blob-stored", Array.concat([("too_large", #rejected)], onWrite)),
    op("upload_begin", "blob-upload-begin", "blob-upload", [("unplaceable", #rejected)]),
    op(
      "upload_append",
      "blob-upload-append",
      "blob-upload-state",
      [
        ("not_found", #rejected),
        ("wrong_offset", #rejected),
        ("too_large", #rejected),
        ("storage_full", #unavailable),
      ],
    ),
    op("upload_describe", "blob-upload-name", "blob-upload-state", [("not_found", #rejected)]),
    op(
      "upload_finish",
      "blob-upload-name",
      "blob-stored",
      [("not_found", #rejected), ("size_differs", #rejected), ("storage_full", #unavailable)],
    ),
    op("upload_abort", "blob-upload-name", "blob-upload-aborted", []),
    op("get", "blob-get", "blob-content", [("not_found", #rejected)]),
    op("describe", "blob-name", "blob-described", []),
    op(
      "place",
      "blob-place",
      "blob-placed",
      [("not_found", #rejected), ("unplaceable", #rejected)],
    ),
    op("delete", "blob-name", "blob-deleted", []),
    op("list", "blob-list", "blob-listed", []),
    op("rekey", "blob-rekey", "blob-task", [("not_retiring", #rejected)]),
    op("task", "blob-task", "blob-task-of", [("not_found", #rejected)]),
  ],
}
