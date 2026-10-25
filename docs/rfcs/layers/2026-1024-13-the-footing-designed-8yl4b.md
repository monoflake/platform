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

**One footing, written once, an instance per half**, decided by the author on 2026-10-24. The one
footing component is written in monoflake/platform. The platform deploys one instance for its own
half and one for each organization. Each instance accepts only its half's record kinds, as
`model/graph/records.res` lists them, and stands on a vendor database of its own. The halves are
kept apart by instance and database: the platform's instance holds no organization's records, and an
organization's none of the platform's. monoflake/cloud deploys the platform's instance from this
repository's code, which is the two repositories' split, RFC 8lkuv. The interface and samples are
one, so the code is one; what differs is which kinds an instance holds, which `records.res` already
splits by half, and separate instances and databases keep the halves apart more surely than two
codes would. Rejected: two implementations, one interface written and tested twice, bound to
drift. How the model says it is in the Ledger.

**No migration when the footing lands**, decided by the author on 2026-10-24. Both platforms' state
is rebuilt from nothing: organizations opened again, every machine and account bound again, and
hello deployed again. Everything live is test data, and today's ids are sequential against RFC b8f35
and would be drawn again anyway; a one-shot migration would be code written and tested to run once.
Rejected: a migration script carrying the rows across.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **One generation counter per footing instance**, provisional, chosen by the advisor on 2026-10-24,
  advanced by the footing itself in the same batch as every write it applies. The `generation` row
  is the footing's to write, not the control's, and `records.res` says so. No configuration sample
  assumes generations step by one with configuration alone: every generation in
  `tests/products/configuration/` is matched as any, captured or used again, never a number.
- **History is kept for configuration kinds alone**, provisional, chosen by the advisor on
  2026-10-24, the kinds the control writes. `read` gains an optional generation for those kinds,
  answering rows as they were then, deleted ones absent. Data-plane kinds keep no history, so a
  frequent `lease` or `writer` row costs none.
- **The bundle is a record kind `bundle`, keyed by generation**, provisional, chosen by the advisor
  on 2026-10-24, written by the control alone through `write`, as its other rows are. It is read
  whole through `bundle`, as `footing-bundle` says, since its signature covers every section; a
  reader takes its section after verifying. RFC b8f35's `origin` is dropped from its key: an
  instance holds one half's bundles alone, so there is nothing left for it to tell apart.
- **A new row's id is drawn by the footing**, provisional, chosen by the advisor on 2026-10-24: 8
  hex digits at random, checked by a conditional insert and drawn again on a conflict, in one space
  per scope across every kind, RFC b8f35. A content's id is its BLAKE3 hash and never drawn. A
  write whose "absent" condition meets an existing unique key answers `stale`, since its condition
  failed.
- **A lease's holder is the instance**, provisional, chosen by the advisor on 2026-10-24, named by
  the `kid` of its instance key, never the component's `sub`, so two instances of one component are
  told apart and `single_instance` can hold. `until` is in milliseconds, RFC b8f35. `seconds` is 30
  when absent and at most 300. Only the holder renews or releases; another's `take`, `renew` or
  `release` while it is held answers `held`, and once it lapses anyone may take it.
- **Bounds are set below D1's own limits with a margin and declared in the footing's contract**,
  provisional, chosen by the advisor on 2026-10-24, D8: a row's size, a change's rows and bytes,
  `limit`'s default and most, and `next` an opaque cursor. D1's own, as Cloudflare states them: a
  row, string or BLOB 2,000,000 bytes, a statement 100,000 bytes, 100 bound parameters a query, a
  batch one query of an invocation and bounded by the 30 seconds a query may run. The footing's, as
  the integrator proposed them and the advisor accepted on 2026-10-24: a row's content at most
  1,000,000 bytes; a change at most 100 rows and 4,000,000 bytes; `limit` 100 when absent and at
  most 1,000, a page ending early past 4,000,000 bytes; `next` opaque bytes.
- **Each `write` is one D1 batch, all or none**, provisional, chosen by the advisor on 2026-10-24.
  Group commit is not built now. Reads go to D1's primary, so RFC e69rc stays a draft with nothing
  stale to bound yet.
- **Where two RFCs disagree, the later decision holds**, provisional, chosen by the advisor on
  2026-10-24, as done already for RFC b8f35 against RFC 7xpd3. `records.res` has the extent write
  `parcel` and `journal`, with the `record.journal` edge it lacked. RFC vr5lw, worked out on
  2026-10-18, holds a database's writer by a lease in the footing; RFC vuanj, decided by the author
  on 2026-10-20, holds it by whatever gives it, its lease the copies' own and never a row of the
  footing. By that rule RFC vuanj's holds, the later: a database's writer is held by its
  provider, its lease the copies', never a row of the footing; nothing in the model held it
  otherwise. The clock's table stays on the machine's disk, RFC p6fg3.
- **The footing's bench**, provisional, chosen by the advisor on 2026-10-24, RFC 9bq0y: two
  instances of one component with distinct keys, so `lease` and `single_instance` are tested; `wait`
  sleeps where the footing's clock cannot be held, marked slow, RFC p8e8k; `cases.res` adds the
  footing to the components and a records seed to `given`.
- **The model declares the footing once**, provisional, chosen by the advisor on 2026-10-24:
  `footing(half)` in `model/graph/components.res` makes both nodes, `footing(organization)` and
  `footing(platform)`, and monoflake/cloud's fill holds no copy. The half rule reads every node
  answering `footing`, over any edge, so an organization's component reaching `footing(platform)`
  is reported, and a test holds it. An instance learns its half from its own certificate chain.
- **The footing's callers are generated at build from the merged model**, provisional, chosen by the
  advisor on 2026-10-24, RFC jy0s5: the platform's instance is built in monoflake/cloud with its
  fill, so its callers come from there. A caller's `sub` maps to design names by the model: the
  footing allows a component what the names it provides may do, RFC s42ex's `provides`, so one
  providing `authority` writes what `authority` writes. An edge reading the platform's footing's
  rows carries the footing's contract, `footing`, as monoflake/cloud's RFC 6dheo strikes its own
  undeclared contract for the records.
