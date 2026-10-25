---
name: 'A Host Bound Joins the Roster'
title: "Binding a host is adding a place to the roster: the driver's edge goes to `?roster`, and `bindings` is the roster's interface for a host added and reporting itself"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

monoflake/driver gives driver(machine) an edge of its own to `control(organization)` carrying
`bindings`, `model/contracts/products/bindings.res`, RFC rxmd9: `open` by the operator, `bind` by
the host. No component of the design answers `bindings`, so the as-built graph, RFC s42ex, reports
the edge as a Crossing in every deployment. `?roster`, `model/graph/boundaries.res`, lists the
places that can run something, and a place added or removed is the control plane's; the
organization's control already provides `?roster`, `model/graph/provided.res`.

## Decision

Decided by the author on 2026-10-24.

**Binding a host is adding a place to the roster.** The driver's edge targets `?roster`, carrying
`bindings`, and `bindings` is recorded as the roster's interface for a host added and reporting
itself, `interfaces` of a boundary in `model/graph/boundaries.res`. The as-built graph then resolves
the edge through `control(organization)`, which provides `?roster`, so the Crossing goes, and
`?roster` stays a scaffold, as it truly is.

Rejected: a mechanism letting a block declare answers the design does not give it, since that would
let the as-built graph depart from the design by rule, where RFC s42ex holds both to the same rules;
and leaving the Crossing reported.

RFC 7i2at, how a host is bound, narrows to one open question, who may open a binding; its other
parts are answered by RFCs 3d3nt and rxmd9.
