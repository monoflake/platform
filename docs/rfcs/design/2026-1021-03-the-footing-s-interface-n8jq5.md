---
name: "The Footing's Interface"
title: "How a component reads and writes its footing: one interface the footing's own Worker answers, records by kind and key, writes conditional, leases by the footing's clock"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC b8f35 puts a footing on Cloudflare as D1 behind a footing Worker of the same account, reached
by a service binding from a Worker and over HTTPS with a capability from a machine; every write a
conditional statement, commits grouped into batches. `model/graph/records.res` says which half and
which component writes each kind, and `model/graph/components.res` draws every edge to
`footing(organization)` with the records and bundle sections it reads. What the footing Worker
answers is written nowhere: no interface names it, no library reaches it, and whether a component
sends SQL or calls operations is not said. blob and the issuer cannot be written until it is; the
executor, which stores nothing, RFC vuanj, needs none of it.

Found while reading, and to be settled with this: `records.res` names compute and the executor as
writers of `lease`, and neither has an edge to `record.lease`; vuanj says the executor stores
nothing.

## Decided

Decided by the author on 2026-10-21, from the agent's proposal.

1. **The footing is an interface, `footing`, declared in the model as every other is**,
   `model/contracts/components/footings.res`, `POST /footing/{operation}`, its answers `answer`
   envelopes, RFC ge55b, so the footing Worker on Cloudflare and whatever answers it on a machine are
   held to one set of samples, `tests/components/footing/`, RFC p8e8k, and no component writes SQL
   against a schema it does not own. Four operations:
   - `read`: a record by kind and key, or a kind's records by a prefix of a unique key, a page at a
     time; each with the generation that wrote it.
   - `write`: records of one change, each conditional, absent or at the generation read, applied all
     or none, answered `stale` where any condition failed, the generation it made given back.
   - `bundle`: the newest signed bundle and its generation, or a section of it, for a reader that
     verifies it, `capability*`, refusing a generation lower than one it read, RFC v7v3w.
   - `lease`: a lease taken, renewed or given up, by name, `until` set by the footing's clock and
     never a host's, answered `held` while another holds it.
2. **Who may write what is the capability's**: a call carries a capability whose target names the
   kinds its caller writes, as `model/graph/records.res` lists them, a case `records` of
   `capability-target` in `model/contracts/signed/signed.res`, which raised `capability` to version
   3; so the data plane's writing no configuration is held where it is written, not trusted.
3. **A machine reaches the same interface**: a host on a machine calls the footing Worker over
   HTTPS, RFC b8f35, and a footing on a machine, where one is, answers the same operations; the
   machine footing's engine is the machine's, behind them.
4. **`lease` is written by compute alone**: the executor stores nothing, vuanj, so it left
   `records.res`'s writers of `lease`, and compute has the `record.lease` edge it lacked.

## Open

What a reader caches of a bundle, and how soon it sees a newer one, stays C36's. How long a read
may be stale, given D1's read replicas need a session's bookmark, `docs/lessons/cloudflare.md`, is
for when the footing Worker is written.
