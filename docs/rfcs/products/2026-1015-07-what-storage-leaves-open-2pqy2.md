---
name: 'What Storage Leaves Open'
title: 'What the storage still asks: where its metadata is held, one content in two kinds of bucket, a store lost, and how copies are laid out'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC 13ixj.

Open, for the discussion that follows:

- Whether that metadata is held per owner or per bucket. Deduplication and the count of names
  pointing at each hash are an owner's, which argues for per owner. [C9]
- Whether one content named in a `packed` and an `opaque` bucket is kept once, and how. [C8]
- What follows when a store is lost without warning, or reaches an end its owner did not choose.
  [C20]
- Whether copies are laid out whole or as shards with parity, and whether the owner sees which.
  [C21]
