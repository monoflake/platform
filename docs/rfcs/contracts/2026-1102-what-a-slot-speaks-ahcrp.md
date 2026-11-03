---
name: 'What a slot speaks'
title: "A slot speaks the contract of the product it reaches, never the driver kind's beneath it, so a storage slot reaches the storage product's buckets"
status: decided
supersedes: []
references: []
---

## Question

RFC rt6gi has a function reach a slot as `env.<slot name>`, speaking "the kind's own contract", its
operations and types those of `model/contracts/kinds/`. For a database the product and the kind are
one contract, so `env.database` is both. For storage they are two: the storage product of RFC
13ixj, its buckets in `model/contracts/products/buckets.res`, stands above the driver's `object`
kind, `model/contracts/kinds/objects.res`, which RFC vr5lw places beneath the products. Read as
written, rt6gi would hand an app the `object` kind, past the product that owns names, extensions
and content. Which contract does a slot speak?

## Options

- **A**: the product's contract. An app reaches what a product offers it, the storage product's
  bucket for storage, and only the product reaches the kind beneath it. Where product and kind are
  one contract, as for a database, nothing changes.
- **B**: the kind's contract, as rt6gi reads. Thinner on a machine, but an app would hold the
  driver's object keys and bypass the product's names, extensions and keyed content, against
  vr5lw's layering and 13ixj.

## Decision

Decided by the author on 2026-11-03, A, asked in thread fifth's decision queue.

- **A slot speaks the contract of the product it reaches**, never that of the driver kind beneath
  it. This replaces rt6gi's line that a slot speaks the kind's own contract; the rest of rt6gi
  stands, `env.<slot name>`, the same types in every home and no credential in the function.
- **For a database the product and the kind are one contract**, so `env.database` and the code
  behind it stay as they are.
- **For storage an app reaches the storage product**, `model/contracts/products/buckets.res`,
  never the driver's `object` kind, which only the product reaches.
- **On Cloudflare a storage slot binds to a product Worker**, not to the driver's own object
  Worker, when that home is built.
- Rejected: B, a kind's contract handed to an app past its product.
