---
name: 'What the Directory Answers'
title: "The contract between a scope, its backing and the role that finds them: a scope's id, its status and where its backing is, a row never removed"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC 8lkuv names what a scope and its backing need of the platform half a role of its own, since
the platform half is the other repository's. What it holds is settled, RFC b8f35: a row a scope,
its id, its status of `active`, `suspended` or `deleted`, and a reference to where its backing is,
never removed so an id is never given twice. The edges from `scope` and `backing` to it are drawn,
and their contract is undeclared, `?directory`.

## Decided

**The contract is the reading alone**, decided by the author on 2026-10-20: this half reads the
directory and never writes it. Opening, suspending, restoring and deleting a scope are the
authority's own writes to its directory, the platform half's own, so a team running its own
writes the one row its one scope needs, once.

**A row crosses as the scope's id, its status and where its backing is**, decided by the author on
2026-10-20: the id in RFC b8f35's form of eight hex digits, one of the three statuses, and the
place in a footing where the scope's backing is kept, which the scope's components can reach. A row
is signed in a chain to the root, as the authority's record is, RFC 7xpd3; its fields are written
as the contract is declared.

**It is read by what reads a backing**, decided by the author on 2026-10-20: a scope and its
backing are concepts and never processes, RFCs vuanj and b8f35, so the edges drawn from them are the
blob's and the extent's, each reading where its scope's backing is kept.

**It is read at deployment, and only then**, decided by the author on 2026-10-20: a suspension
reaches an organization by the authority's record, its status there and a notice of the change,
RFC 7xpd3, never by the directory, which answers where a backing is, and that changes only as a
backing moves, when what reads it is deployed again.

**The contract is declared**, decided by the author on 2026-10-20,
`model/contracts/roles/directories.res`, its cases in `tests/kinds/directories/`: one operation,
`row`, a call the reader signs with its certificate, answering the row as a record the authority
signs, `monoflake:directory:1`. **A row is never removed**, so a scope deleted answers as deleted
and only an id never opened is not found. **Being signed, a row may come with the deployment of
what reads it**, verified the same way, so reading it is the deployer's choice and never a trust.
**A scope's status is one type wherever it is said** -- a row, the authority's record, a bundle --
`active`, `suspended` or `deleted`, a bundle never saying the last, since a scope deleted has none.
