---
name: 'What a Binding Offers and Adopts'
title: "A driver's management says which kinds its binding offers, takes the resources an organization's admin lists as the driver's own, and warns of what a person should act on"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

monoflake/driver's RFC nrs5v, amended by the author on 2026-10-24, binds an organization's own
account, which may already hold resources of the organization's own. There a binding offers only
some kinds, chosen as the driver is installed; the organization's admin may list named resources
the driver also manages, each standing for what the platform asks; and a listed resource is never
deleted, so the admin is told to delete it by hand. Management, RFC vr5lw, has no field for any of
the three: `management-described` holds the generation, the policy, the grace, the items and the
revision, and `management-apply` the generation, the items and the tokens.

## Decision

Decided by the author on 2026-10-24, in RFC nrs5v: the exception list holds exact names only, never
patterns, and a listed resource is only ever updated, never deleted; which kinds a binding offers is
chosen at install. What it asks of management is written here, since the contract is this
repository's; it is neutral, using the platform's kind names, never a vendor's resource words.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **The fields go in management's interface, optional fields only**, provisional, chosen by the
  advisor on 2026-10-24, so the version stays 2, as `revision` was added under RFC wnqvu.
- **`management-described` gains three**, provisional, chosen by the advisor on 2026-10-24:
  - `kinds`, key 6, optional: the kinds this binding offers. Absent means every kind the model gives
    that driver.
  - `adopted`, key 7, optional: the exception list as held.
  - `warnings`, key 8, optional: what a person should act on.
- **`management-apply` gains `adopted`, key 4, optional**: the exception list, provisional, chosen
  by the advisor on 2026-10-24.
- **An `adopted` entry is `{kind, name, for}`**, provisional, chosen by the advisor on 2026-10-24:
  - `kind` is one of `function`, `object`, `database`;
  - `name` is the exact name of the resource on the bound host;
  - `for` is what it stands for, a union: for `function`, the deployment as the deployments
    interface identifies it, an app's id or a component's name; for `object` and `database`, the
    management item's id.
- **A warning is `{reason, message, name}`**, provisional, chosen by the advisor on 2026-10-24. The
  first reason is `delete_by_hand`: a listed resource released, which the admin should delete in the
  vendor's own dashboard, kept until that resource no longer exists.
- **driver(machine) answers too**, provisional, chosen by the advisor on 2026-10-24: `kinds` as it
  offers them; a non-empty `adopted` refused as `beyond_host`, since a machine has no prior
  resources to adopt; no warnings.
- **Samples for each field go in `tests/kinds/`** with documentation values, provisional, chosen by
  the advisor on 2026-10-24.
