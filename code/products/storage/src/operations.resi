/***
 * The object bucket's five operations over the `object` kind, buckets.res's `object_*`, content
 * held once by its keyed hash and each object an empty name beside it, RFC 13ixj. The model's
 * interface, `docs/code.md`.
 */
open Envelope

/** The `object` kind as storage calls it, each answer as the kind gives it, RFC vr5lw. */
type objects = {
  write: Contracts.ObjectWrite.t => promise<Contracts.Answer.t<Contracts.ObjectWritten.t>>,
  read: Contracts.ObjectRead.t => promise<Contracts.Answer.t<Contracts.ObjectContent.t>>,
  describe: Contracts.ObjectName.t => promise<Contracts.Answer.t<Contracts.ObjectDescribed.t>>,
  delete: Contracts.ObjectName.t => promise<Contracts.Answer.t<Contracts.ObjectDeleted.t>>,
  list: Contracts.ObjectList.t => promise<Contracts.Answer.t<Contracts.ObjectListed.t>>,
}

/** What every operation is given, the organization's salt of 32 bytes and the kind. */
type context = {salt: Uint8Array.t, objects: objects}

/**
 * Content past the kind's most refused as `too_large`, its extension as `extension_invalid`; the
 * content written once under its hash, then the object's name, the object already there answered
 * again.
 */
let write: (
  context,
  Contracts.BucketObjectWrite.t,
) => promise<Contracts.Answer.t<Contracts.BucketObject.t>>

/** An object not named answers `not_found`; one whose content is gone answers `unavailable`. */
let read: (
  context,
  Contracts.BucketObjectRead.t,
) => promise<Contracts.Answer.t<Contracts.ObjectContent.t>>

/** Its content's size, absent where no object is named; content gone answers `unavailable`. */
let describe: (
  context,
  Contracts.BucketObjectName.t,
) => promise<Contracts.Answer.t<Contracts.ObjectDescribed.t>>

/** Removes the object's name alone, never the content, and succeeds where none is named. */
let delete: (
  context,
  Contracts.BucketObjectName.t,
) => promise<Contracts.Answer.t<Contracts.ObjectDeleted.t>>

/** The bucket's objects after `after` in byte order, at most `limit`, with hash and size. */
let list: (
  context,
  Contracts.BucketObjectList.t,
) => promise<Contracts.Answer.t<Contracts.BucketObjectListed.t>>
