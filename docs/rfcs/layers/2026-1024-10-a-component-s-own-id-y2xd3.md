---
name: "A Component's Own Id"
title: "A component deployed into a scope is that scope's resource, a record of kind `component` whose id the deployer draws, and a deployment of it names that id"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFC b8f35 has an id of 8 hex digits name one resource of a scope and carry its type, whatever its
kind. monoflake/driver's RFC nrs5v, decided by the author on 2026-10-24, names what a driver holds
for the platform by that resource's id, bare, so a deployment's Worker is named by its deployment's
id. `deployment-runs`, `model/contracts/kinds/deployments.res`, identifies an app by its id but a
component by its name alone, so a component's deployment has no id to be named by.

## Decision

Decided on 2026-10-24, following RFC b8f35 and the author's rule that every resource in an
organization carries the organization-unique id, whatever its kind.

**A component deployed into a scope is that scope's resource**, a record of kind `component` in the
organization's half, `model/contracts/records/control.res`, and `deployment-runs`' `component` case
gains its `id` beside its name. The deployer draws the id, the control above the binding, as it
draws every id in the scope; a driver never does, being beneath the scope and minting only ids for
its own parts.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **The id names a record of kind `component`**, provisional, chosen by the advisor on 2026-10-24, as
  it follows from RFC b8f35: an id with no record kind behind it breaks an id naming one resource and
  carrying its type, and the model could no longer tell what the id names. One record per component
  deployed into the scope; its fields are the component's name as the model names it, and nothing
  more until a sample needs more; its writer is the control, the deployer, which draws its id as it
  first deploys that component into the scope; its id is never given to anything else, as every id
  is. Its name is unique among the kind's rows, as `scope` keeps its own; it declares no history
  or deletion, as no kind of its half does.
- **`id` is required, and the interfaces using it are raised**, provisional, chosen by the advisor
  on 2026-10-24: `deployments` one version, `management` 2 to 3. Every caller and both drivers are
  ours and nothing is released; a required field now is a mechanical change, and an optional one
  now a known break later, plus a field whose absence means "not given yet", which RFC b8f35 rules
  out. `management` 3 also holds RFC vbg0u's fields.
- **Until the control deploys components, the bench draws a component's id**, provisional, chosen by
  the advisor on 2026-10-24, as it plays the deployer for everything else, RFC 9bq0y; so a driver
  always has an id to name a component's Worker by.
