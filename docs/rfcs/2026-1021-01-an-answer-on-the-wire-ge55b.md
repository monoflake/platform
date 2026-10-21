---
name: 'An Answer on the Wire'
title: "How an answer is told from an error over HTTP, and what an image's artifact is and its hash"
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

## Proposed

Written by the agent on 2026-10-21 for the author to decide; code that needs an answer now takes
the proposal and cites this RFC, so a decision otherwise is one change in two places.

1. **By the HTTP status, and nothing in the body**: an output is `200`; an `error` is `400` where its
   failure is `rejected`, `503` where `unavailable`, `500` where `unknown`, its body the `error`
   record in the form the request asked. A status a reader does not expect -- a proxy's `502`, a
   `404` from something that is not the platform -- is `unknown`, reason `malformed`, since nothing
   the platform answered was read. The status is the one thing every HTTP client, cache and proxy
   already reads, and it keeps the body exactly the contract's type.
2. **An image's artifact is an OCI image layout archive**, a tar holding `oci-layout`, `index.json`
   and `blobs/`, as `docker buildx` writes with `type=oci` and `ctr images import` reads; its
   `address` an HTTPS URL the archive is fetched from, and its `hash` the SHA-256 of the archive's
   bytes as fetched, checked before anything is imported, so `hash_mismatch` and `too_large` are
   decided on the bytes alone. An archive holds one platform's image; the deployment names the
   architecture by the machine it lands on.

## Open

Whether a registry replaces the archive later, and then whether `hash` becomes a manifest's digest,
is C11's with the image's format.
