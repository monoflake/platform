---
name: 'A Name Filled From Beneath'
title: "A deployment says a name is filled by the platform beneath it, which the check follows into that deployment's column and holds to RFC 94y0d's one way down"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC s42ex derives each deployment's as-built graph from what fills each of its names, RFC vgvx6:
a block, a vendor's resource or a user's workload, `model/graph/provided.res`. A platform standing
on another, RFC 94y0d, takes some of its names from the platform beneath, its footing, its objects
and its reach among them, and no filler can say so; a column then lacks those names, and the path
it really takes down is described in prose alone.

## Decision

Decided by the author on 2026-10-24.

**A fourth filler, `Beneath`, names the deployment beneath and the name it provides there.** The
check follows it into that deployment's column and holds that the name is provided there. It holds
RFC 94y0d's rule as well: the platform above reaches the one below only through a product's contract
at layer 0, so a path down through anything else is reported as a violation by derivation, not by
prose. Rejected: writing the deployment beneath as a vendor, which the check cannot see into, and
leaving the gap. The model sees the whole hosted platform and should see this dependency; RFC
94y0d's "as on any vendor" is the view from inside the platform above.

The variant is generic: it names a deployment by the string the deployment's own repository gives
it, and holds nothing of any one deployment.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **`Beneath` is built on the existing `beneath` node**, provisional, chosen by the advisor on
  2026-10-24: a name a column fills by `Beneath` is provided there by `Provided.beneath`, so an edge
  to it goes to `beneath`, as an edge marked `beneath` does, and in that column `beneath` stands for
  the deployment the `Beneath` names. The check follows it into that column and holds that the name
  is provided there; and a name taken down must be a product at layer 0, one `beneath` answers, or it
  is reported among that column's scaffolds as against RFC 94y0d.
- **Fill it as it truly is**, provisional, chosen by the advisor on 2026-10-24: the production
  column's `footing(organization)` is `Beneath({deployment: "foundation", name:
  "control(organization)"})`, so check two reports the violation, the relay path reported by
  derivation, not by prose. The as-built graph states what runs, never what RFC 94y0d expects, RFCs
  s42ex and vgvx6; writing `database` would make the derivation lie to stay quiet.
- **Only `footing(organization)` is filled now**, provisional, chosen by the advisor on 2026-10-24.
  Which design names the objects and the reach taken down stand for is decided from the derivation's
  report of the production column, not guessed now.
- **One deployment beneath per column**, provisional, chosen by the advisor on 2026-10-24: every
  `Beneath` in a column names the same deployment, and never the column's own, or it is reported as
  mistaken. RFC 94y0d has a platform stand on one other, and nothing yet designs two.
- **An edge marked `beneath` goes to `beneath` only in a column holding a `Beneath`**, chosen by the
  integrator on 2026-10-24 to follow the entry above, for the advisor to read: a column with none has
  no platform beneath, so such an edge is no edge there.
