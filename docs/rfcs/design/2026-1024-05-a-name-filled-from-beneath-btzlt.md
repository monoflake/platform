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
- **Fill it as it truly is**, provisional, chosen by the advisor on 2026-10-24: a column standing
  on another fills its `footing(organization)` by the name that really keeps it there, that
  column's control where it does, so check two reports the violation, the relay path reported by
  derivation, not by prose; the hosted platform's own fill is monoflake/cloud's. The as-built graph states what runs, never what RFC 94y0d expects, RFCs
  s42ex and vgvx6; writing `database` would make the derivation lie to stay quiet.
- **Only `footing(organization)` is filled now**, provisional, chosen by the advisor on 2026-10-24.
  Which design names the objects and the reach taken down stand for is decided from the derivation's
  report of the column standing on another, not guessed now.
- **One deployment beneath per column**, provisional, chosen by the advisor on 2026-10-24: every
  `Beneath` in a column names the same deployment, and never the column's own, or it is reported as
  mistaken. RFC 94y0d has a platform stand on one other, and nothing yet designs two.
- **An edge marked `beneath` goes to `beneath` only in a column holding a `Beneath`**, chosen by the
  integrator, accepted by the advisor on 2026-10-24: a column with none has no platform beneath, so
  such an edge is no edge there.
- **The Crossing does not report again what check two reports**, provisional, chosen by the advisor
  on 2026-10-24. One fact is reported once, as the duplicated cycle was deduplicated; check two's
  line is the one that names RFC 94y0d, which is the reason.
- **The Provided report lists every name a column fills explicitly**, provisional, chosen by the
  advisor on 2026-10-24, `Vendor`, `Workload` and `Beneath` alike, so a footing a vendor's resource
  fills shows as filled by it. A report that lists one filler's
  names and hides another's misleads by omission.
- **Check one is read literally, with one addition**, provisional, chosen by the advisor on
  2026-10-24. A chain of `Beneath` is followed to its end, and a chain that comes back to a column
  already passed is mistaken, two columns standing on each other among them. An unbuilt Block counts
  as providing in check one, since its own column already reports it as unbuilt.
- **Each name a `Beneath` fills keeps its own node in that column**, provisional, chosen by the
  advisor on 2026-10-24, after review. It carries the filled name's own attributes, its layer, kind,
  half and role, and is marked as provided from beneath; check two judges the name taken from
  beneath, whether it is a product at layer 0 the beneath node answers. The generic `beneath`
  node stays for the edges marked `beneath` alone, judged only by its own answers. Rejected:
  reporting mistaken when several filled names differ, which would forbid a column filling the
  footing and `?clock` from beneath alike, as decisions of 2026-10-24 do.
- **Check two passes a product at layer 0 by its name or its contracts**, provisional, chosen by the
  advisor on 2026-10-24, after review: a component at layer 0 passes when its own name or any of its
  answers is among the beneath node's answers, so `compute` passes as `storage` and `database` do.
- **A name filled through a `Beneath` that check one or two finds wrong is not rightly provided** in
  the Frontier, provisional, chosen by the advisor on 2026-10-24, after review.
- **A scaffold's line keeps the name an edge went to**, provisional, chosen by the advisor on
  2026-10-24, after review, as `-> footing(organization) (beneath)`. The suffix is added: a scaffold
  line that names the filled name alone hides the very fact the line exists to show, that the name
  is provided from beneath.
- **Every contract the filled name answers must be answered by the name taken from beneath**, or the
  column reports it as mistaken, provisional, chosen by the advisor on 2026-10-24. Being a layer-0
  product is necessary but not enough: filling `footing(organization)` by `database` would pass
  while the footing's `footing`, `records` and `bundle` go unanswered.
