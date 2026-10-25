---
name: 'The Footing Designed'
title: "The footing is a component the platform writes and holds to samples, standing on ground that is the vendor's database, which it alone reaches"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

`docs/scope.md` called the footing ground, "trusted and never designed": SQLite's dialect, atomic
batches, at most 10 GB, stood on by a control alone, and the model followed it, the footing a
ground node with no language, edges or samples. RFC n8jq5, landed, made the footing an interface its
own Worker answers, held to samples in `tests/components/footing/`, so that no component writes
SQL; and every component's edges reach it. What is the footing, a ground or a component?

## Decision

Decided by the author on 2026-10-24: **two layers.** It changes what RFC n8jq5 and `docs/scope.md`
left the footing, and RFC n8jq5 stands as written for its interface.

- **The footing is a component of the design**, with a language, `key()`, edges and samples, at a
  layer below the components that call it. It answers RFC n8jq5's interface, `read`, `write`,
  `bundle` and `lease`, to every component.
- **It stands on ground, the vendor's database**, under `docs/scope.md`'s frozen contract, SQLite's
  dialect, atomic batches, at most 10 GB and reached from every compute, trusted and never designed.
- **The footing component alone stands on the vendor's database**, and every other component reaches
  it through the footing's interface, RFC n8jq5's "no component writes SQL"; this replaces
  `docs/scope.md`'s "a control stands on it and nothing else does".
- Rejected: keeping the footing as ground a block provides. Ground is never tested, yet RFC n8jq5
  holds it to samples, and it is code the platform writes, not a vendor's guarantee.
- The rule this keeps: what the platform writes is designed and held to samples; only a vendor's
  written guarantee, a published standard, a proven algorithm or a physical fact is ground.
- The `?tables` scaffold, the control writing SQL past the footing's interface, retires when the
  control reaches the footing through it. A machine's footing waits on driver(machine)'s database,
  so Cloudflare's comes first, a Worker in front of D1.

**An organization's footing lives on the platform's own ground**, decided by the author on
2026-10-24, never on the organization's bound account. A platform runs the footings of its
organizations on its own ground, deployed as its control is, the database bound at that deploy by
the platform's own tooling, so no driver is involved and a driver's deploy carrying no binding does
not stand in the way. An organization's own bound accounts and machines hold only its workloads,
never its footing. The footing holds an organization's grants and configuration, the platform's
record of it, so it belongs where the platform keeps things, not where the organization may delete
them. Rejected: the footing on the organization's bound account, deployed by a driver, which waits
on the binding gap, costs the organization's account a database, and would leave with the account
the record the platform manages the organization by. A platform standing on another takes its
organizations' footing from the platform beneath, its public export imported, RFC nge39, which
replaces a relay; the model draws `footing(organization)` on `database(vendor)`, the vendor's
database, whoever's account a deployment puts it on.
