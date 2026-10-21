/**
 * The storage product's interface, an app's, RFCs 13ixj and vr5lw: the files of a file bucket and
 * the objects of an object bucket, and `publish` between them. A bucket itself is configuration,
 * made and ended through its organization's control, `generations.res`, so nothing here makes one.
 * Products are named by what they carry, in the plural, as the kinds are.
 */
open Subset

let types: array<declared> = [
  // What a write to a path asks of what is there: nothing, the path new, or the content it names.
  {
    name: "file-expected",
    def: Union({
      tag: "name",
      cases: [
        {name: "absent", code: 1, fields: []},
        {name: "hash", code: 2, fields: [field("hash", 1, Prim(#hash))]},
      ],
    }),
    from: "13ixj",
  },
  {
    name: "file-write",
    def: Record([
      field("bucket", 1, Id("bucket")),
      field("path", 2, Prim(#string)),
      field("content", 3, Prim(#bytes)),
      optional("expected", 4, Type("file-expected")),
    ]),
    from: "13ixj",
  },
  {
    name: "file-written",
    def: Record([field("hash", 1, Prim(#hash)), field("size", 2, Prim(#uint53))]),
    from: "13ixj",
  },
  {
    name: "file-read",
    def: Record([
      field("bucket", 1, Id("bucket")),
      field("path", 2, Prim(#string)),
      optional("range", 3, Type("object-range")),
    ]),
    from: "13ixj",
  },
  // The whole file's size and hash beside what was read of it.
  {
    name: "file-content",
    def: Record([
      field("content", 1, Prim(#bytes)),
      field("size", 2, Prim(#uint53)),
      field("hash", 3, Prim(#hash)),
    ]),
    from: "13ixj",
  },
  {
    name: "file-path",
    def: Record([field("bucket", 1, Id("bucket")), field("path", 2, Prim(#string))]),
    from: "13ixj",
  },
  // Its hash and size, both absent when no file is there.
  {
    name: "file-described",
    def: Record([optional("hash", 1, Prim(#hash)), optional("size", 2, Prim(#uint53))]),
    from: "13ixj",
  },
  // A delete that names a hash removes the path only while it names that content.
  {
    name: "file-delete",
    def: Record([
      field("bucket", 1, Id("bucket")),
      field("path", 2, Prim(#string)),
      optional("expected", 3, Prim(#hash)),
    ]),
    from: "13ixj",
  },
  {name: "file-deleted", def: Record([]), from: "13ixj"},
  // A file of any size is written by an upload, as the blob's is, vuanj: begun at its path, its
  // size held to where it is known and its expectation asked as it finishes, when the path is
  // pointed at what it wrote.
  {
    name: "file-upload-begin",
    def: Record([
      field("bucket", 1, Id("bucket")),
      field("path", 2, Prim(#string)),
      optional("size", 3, Prim(#uint53)),
      optional("expected", 4, Type("file-expected")),
    ]),
    from: "13ixj, vuanj",
  },
  {
    name: "file-upload",
    def: Record([field("upload", 1, Prim(#hash)), field("part", 2, Prim(#uint53))]),
    from: "13ixj, vuanj",
  },
  {
    name: "file-upload-append",
    def: Record([
      field("upload", 1, Prim(#hash)),
      field("offset", 2, Prim(#uint53)),
      field("content", 3, Prim(#bytes)),
    ]),
    from: "13ixj, vuanj",
  },
  {
    name: "file-upload-name",
    def: Record([field("upload", 1, Prim(#hash))]),
    from: "13ixj, vuanj",
  },
  {
    name: "file-upload-state",
    def: Record([field("received", 1, Prim(#uint53)), field("durable", 2, Prim(#uint53))]),
    from: "13ixj, vuanj",
  },
  {name: "file-upload-aborted", def: Record([]), from: "13ixj, vuanj"},
  // One level of a directory, `directory` empty for the top or a path ending in `/`; entries after
  // `after` in byte order, at most `limit`, a thousand unless set.
  {
    name: "file-list",
    def: Record([
      field("bucket", 1, Id("bucket")),
      field("directory", 2, Prim(#string)),
      optional("after", 3, Prim(#string)),
      optional("limit", 4, Prim(#uint32)),
    ]),
    from: "13ixj",
  },
  // A directory's size and count are kept as each write lands, so a listing reads them, 13ixj.
  {
    name: "file-entry",
    def: Union({
      tag: "type",
      cases: [
        {
          name: "file",
          code: 1,
          fields: [
            field("name", 1, Prim(#string)),
            field("hash", 2, Prim(#hash)),
            field("size", 3, Prim(#uint53)),
          ],
        },
        {
          name: "directory",
          code: 2,
          fields: [
            field("name", 1, Prim(#string)),
            field("size", 2, Prim(#uint53)),
            field("count", 3, Prim(#uint53)),
          ],
        },
      ],
    }),
    from: "13ixj",
  },
  {
    name: "file-listed",
    def: Record([
      field("entries", 1, List(Type("file-entry"))),
      optional("next", 2, Prim(#string)),
    ]),
    from: "13ixj",
  },
  // An object is `{hash}.{extension}`, the extension made standard first, or `{hash}` with none.
  {
    name: "bucket-object-write",
    def: Record([
      field("bucket", 1, Id("bucket")),
      field("content", 2, Prim(#bytes)),
      optional("extension", 3, Prim(#string)),
    ]),
    from: "13ixj",
  },
  {
    name: "bucket-object",
    def: Record([
      field("object", 1, Prim(#string)),
      field("hash", 2, Prim(#hash)),
      field("size", 3, Prim(#uint53)),
    ]),
    from: "13ixj",
  },
  {
    name: "bucket-object-name",
    def: Record([field("bucket", 1, Id("bucket")), field("object", 2, Prim(#string))]),
    from: "13ixj",
  },
  {
    name: "bucket-object-read",
    def: Record([
      field("bucket", 1, Id("bucket")),
      field("object", 2, Prim(#string)),
      optional("range", 3, Type("object-range")),
    ]),
    from: "13ixj",
  },
  // Objects after `after` in byte order, at most `limit`, a thousand unless set.
  {
    name: "bucket-object-list",
    def: Record([
      field("bucket", 1, Id("bucket")),
      optional("after", 2, Prim(#string)),
      optional("limit", 3, Prim(#uint32)),
    ]),
    from: "13ixj",
  },
  {
    name: "bucket-object-listed",
    def: Record([
      field("objects", 1, List(Type("bucket-object"))),
      optional("next", 2, Prim(#string)),
    ]),
    from: "13ixj",
  },
  // The content a path names as it is called, under the path's extension, moving no byte.
  {
    name: "publish",
    def: Record([
      field("from", 1, Id("bucket")),
      field("path", 2, Prim(#string)),
      field("to", 3, Id("bucket")),
    ]),
    from: "13ixj",
  },
]

/** What every operation on a bucket may meet beside its own reasons. */
let onBucket = [("not_a_bucket", #rejected), ("wrong_type", #rejected)]

/**
 * Deleting what is not there, and describing it, succeed, as the object kind's do; a write meets the
 * bucket's quota and its kind's bound. One write carries a part at most, and a file past it is
 * written by an upload, appended to in order and resumed from what is durable, as the blob's is,
 * vuanj; an upload left a day expires, and one whose bucket is deleted ends, each then not found.
 */
let interface_: interface_ = {
  name: "storage",
  version: 1,
  bounds: dict{"opaque": Objects.most, "part": Objects.most},
  from: "13ixj, vr5lw",
  operations: [
    op(
      "file_write",
      "file-write",
      "file-written",
      Array.concat(
        onBucket,
        [
          ("expectation_failed", #rejected),
          ("too_large", #rejected),
          ("quota_exceeded", #rejected),
          ("storage_full", #unavailable),
        ],
      ),
    ),
    op(
      "file_upload_begin",
      "file-upload-begin",
      "file-upload",
      Array.concat(onBucket, [("too_large", #rejected), ("quota_exceeded", #rejected)]),
    ),
    op(
      "file_upload_append",
      "file-upload-append",
      "file-upload-state",
      [
        ("not_found", #rejected),
        ("wrong_offset", #rejected),
        ("too_large", #rejected),
        ("quota_exceeded", #rejected),
        ("storage_full", #unavailable),
      ],
    ),
    op("file_upload_describe", "file-upload-name", "file-upload-state", [("not_found", #rejected)]),
    op(
      "file_upload_finish",
      "file-upload-name",
      "file-written",
      [
        ("not_found", #rejected),
        ("size_differs", #rejected),
        ("expectation_failed", #rejected),
        ("storage_full", #unavailable),
      ],
    ),
    op("file_upload_abort", "file-upload-name", "file-upload-aborted", []),
    op(
      "file_read",
      "file-read",
      "file-content",
      Array.concat(onBucket, [("not_found", #rejected)]),
    ),
    op("file_describe", "file-path", "file-described", onBucket),
    op(
      "file_delete",
      "file-delete",
      "file-deleted",
      Array.concat(onBucket, [("expectation_failed", #rejected)]),
    ),
    op("file_list", "file-list", "file-listed", onBucket),
    op(
      "object_write",
      "bucket-object-write",
      "bucket-object",
      Array.concat(
        onBucket,
        [
          ("extension_invalid", #rejected),
          ("too_large", #rejected),
          ("quota_exceeded", #rejected),
          ("storage_full", #unavailable),
        ],
      ),
    ),
    op(
      "object_read",
      "bucket-object-read",
      "object-content",
      Array.concat(onBucket, [("not_found", #rejected)]),
    ),
    op("object_describe", "bucket-object-name", "object-described", onBucket),
    op("object_delete", "bucket-object-name", "object-deleted", onBucket),
    op("object_list", "bucket-object-list", "bucket-object-listed", onBucket),
    op(
      "publish",
      "publish",
      "bucket-object",
      Array.concat(onBucket, [("not_found", #rejected), ("quota_exceeded", #rejected)]),
    ),
  ],
}
