---
name: 'The footing judges its callers'
title: 'The footing judges each caller by its certificate against the model, never by a capability, and the `records` target goes'
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC n8jq5, landed, decision 2: every footing call carries a capability whose target names the kinds
its caller writes, a `records` case of `capability-target`, which raised `capability` to version 3.
Nothing issues such a capability: the issuer answers `for_app` and `for_space` alone, RFC 4yjq9.
And the issuer reads its grants from the footing, so a capability to read the footing would wait on
the footing itself, a cycle. RFC b8f35 already holds the other way: a component's certificate says
who it is, never what it may do, and what each may ask is the verifier's, written in the model; RFC
vuanj gives a component's own work what its certificate says it is. How does the footing know what
a caller may do?

## Decision

Decided by the author on 2026-10-24. **This replaces RFC n8jq5's decision 2**; its other decisions
stand.

- **A component calls the footing signed by its instance key**, its certificate of role `component`
  in `kcwt`, as RFC 4yjq9 has the issuer call it.
- **The footing verifies the chain to its root, takes the caller's name from `sub`, and allows or
  refuses each operation by the model**:
  - a write by `model/graph/records.res`'s writers of each kind it writes;
  - a read, a bundle or a lease by the edge and contract that caller holds to the footing in
    `model/graph/components.res`, `record.lease`, `bundle.issuer`, `record.writer` and the rest.
- **A caller the model gives no such edge is refused `denied`.**
- **The footing's operations declare `component` as their caller**, RFC 6x8su's declaration, the
  name then held to the model as above.
- **There is no cycle**: the issuer reads its bundle by its certificate, as every other component
  does.
- Kept: RFC n8jq5's aim that the data plane writes no configuration, now held where it is written,
  at the footing, by `records.res`'s writers.
- **Capabilities stay what they are for**: an app's access to data, which an app, holding no
  component certificate, takes from the issuer by its grants.
- **The bench's footing stand-in checks callers the same way once the real footing lands**, RFC
  9bq0y; until then it checks nothing, as now.
- Rejected: keeping the `records` capability, issued by the issuer, with a certificate path carved
  out for the issuer's own reads. That is two mechanisms, and the cycle only stepped around.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **The `records` case of `capability-target` is removed, raising `capability` once more, in its
  own commit**, provisional, chosen by the advisor on 2026-10-24. It has no issuer and no reader.
  Nothing is released, and an unused case left in a signed type is a door nobody watches.
- **A writer of a kind may create, replace and delete its rows**, provisional, chosen by the advisor
  on 2026-10-24, the rights settled by the decision above. Reads, `bundle` and `lease` go by the
  caller's edges.
