---
name: 'An Answer on the Wire'
title: "Every answer one envelope, told by its status, each reason with its message; and what an image's artifact is"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC vr5lw has every operation called as `POST /{interface}/{operation}`, its body a call, answered
by the operation's output or an `error`, in JSON or CBOR as the request asks. Two things are written
nowhere, and the first code that serves a call and the first that calls one -- the shared serving
library, `serve*`, and the samples' runner -- cannot be written without them:

1. **How a reader tells an output from an `error`.** Both are records of the subset, and nothing in
   either's bytes says which it is.
2. **What an image's `deployment-artifact` is.** Its `address` and `hash` are a generic place and a
   generic hash; an image's format waits on C11, and how an image reaches the driver is open, RFC
   vr5lw.

## Decided

Decided by the author on 2026-10-21, after the agent read the author's own response envelope in
`canmi/lib`, `spec/response/envelope.md`, and proposed it be taken over.

- **Every answer is one envelope, `answer`**, as `canmi/lib`'s is: a union by `status`, `success`
  holding the operation's output as `data`, `error` holding its `failure`, its `reason` and its
  `message`, in JSON and in CBOR alike, `model/contracts/subset/subset.res`. A reader tells the two
  by `status` alone; the platform keeps its own names, `reason` where the library says `code`, and
  `failure` beside it, which says whether to try again.
- **A message is always written**, for a person, each reason's own in a catalog,
  `model/contracts/subset/calls.res`'s `messages`, unless the moment says more, as the library's
  codes each carry a default.
- **The HTTP status says as much to what stands between**, and no reader decides by it: `200` an
  output; `400` a `rejected` error, but `403` for `denied` and `404` for `not_found`; `503` an
  `unavailable` one, but `429` for `rate_limited`; `500` an `unknown` one. A body that is no answer
  -- a proxy's `502`, a `404` from something not the platform -- is read as `unknown`, reason
  `malformed`, since nothing the platform answered was read.
- **Load is told by whose it is**: `overloaded`, `503`, where the implementation cannot take more
  for a moment; `rate_limited`, `429`, where the caller calls faster than it is let. Both are every
  operation's.
- **A fault of the implementation's own is `fault`**, `unknown`, `500`, every operation's: what it
  threw, or an output it gave that could not be written, decided by the author on 2026-10-21. A
  reason the operation does not declare is still answered under its own name, `unknown`.
- **CBOR is what a component answers where a request names neither form**, RFC vr5lw.

## Proposed

Written by the agent on 2026-10-21 for the author to decide; the machine driver takes it now and
cites this RFC.

- **An image's artifact is an OCI image layout archive**, a tar holding `oci-layout`, `index.json`
  and `blobs/`, as `docker buildx` writes with `type=oci` and `ctr images import` reads; its
  `address` a URL the archive is fetched from, and its `hash` the SHA-256 of the archive's bytes as
  fetched, checked before anything is imported, so `hash_mismatch` and `too_large` are decided on
  the bytes alone. An archive holds one platform's image.

## Open

Whether a registry replaces the archive later, and then whether `hash` becomes a manifest's digest,
is C11's with the image's format.
