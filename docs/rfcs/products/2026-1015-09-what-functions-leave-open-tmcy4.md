---
name: 'What Functions Leave Open'
title: "What functions still ask: a daemon's credentials and life, the capabilities past the first, a derive's imports, an export's version, storage starting a function, and every bound"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

Left open by RFC 49qyg.

Open, for the discussion that follows:

- How a `keyed` daemon's own credentials reach it, an account's login: env is the same for every
  copy of a deployment, so these may be what it is started with rather than env. [C11]
- How a daemon is started, addressed and ended, given that any may vanish at any moment; a `keyed`
  one, exactly one per key, has the shape of a tablet's writer, placed at run time with at least one
  promised and the rest fenced, RFC vuanj. [C11]
- Every capability past the kind and the network -- where a function's requests leave from, how long
  it may run, its resources -- each of which is at once a need, an allowance and what the platform
  can give, and is entered in the vocabulary when it is taken up. [C11]
- Which imports a `derive` is denied in WebAssembly -- files, the network, the clock, entropy and
  the rest -- examined one by one when it is built. [C11]
- Whether an exported function carries a version, so one can change while its callers move. [C11]
- Whether a change in storage starts a function, perhaps by putting a message in a queue. [C11]
- Every bound: the `derive` budget, the longest wait for a lock and the longest hold, how long an id
  lives, how long an outcome is looked up before it is `unknown`, and how much a dead-letter list
  holds and for how long. [D4]
