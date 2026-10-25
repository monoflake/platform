---
name: 'A Thin Clock on a Machine'
title: "`?clock` at its thinnest: one-shot ticks kept in a table on the machine with driver(machine)'s state, a sleeper firing each at its time or late, delivered at least once"
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

`?clock`, `model/graph/boundaries.res`, delivers a tick at a time asked for to the component that
wrote it, at least once, and is triaged for later. monoflake/cloud's RFC rxmd9 puts every timer on a
machine and none on Cloudflare; its author's clarification of 2026-10-24 allows a one-shot timer an
event sets. monoflake/driver's RFC nrs5v sweeps a Cloudflare binding's grace as each management
request arrives, and since 2026-10-24 also at one tick set at an unasked item's grace end. An
organization may bring a Cloudflare account and no machine, so the first clock is the one of the
platform beneath, served from its machine, and the platform above takes it from beneath. Which way
is it built on that machine? It must be one-shot, kept across a restart, delivered at least once,
and fire a time missed late rather than drop it.

## Options

Ways listed from a reading of the repositories and of systemd's and at's documents on 2026-10-24:
A, a table and a sleeper inside driver(machine); B, that table and a minute's timer declared in the
machine's NixOS module running a firing command; C, a clock daemon apart; D, a persistent timer unit
written to disk for each tick; E, transient timers; F, at; G, a Durable Object's alarm in workerd on
the machine; H, no clock.

## Decision

Decided by the author on 2026-10-24: **A, a table and a sleeper inside driver(machine).**

- The table is persisted with driver(machine)'s state, written atomically as its state is. Due rows
  are fired on start, so a time missed while the driver was down fires late.
- A row is deleted only after a 2xx, which gives at least once.
- A long sleep is cut into segments of the monotonic clock.

It meets all four requirements with the least. Rejected: B, whose extra timer guards a driver that
stays down, while the control the tick reaches runs in that driver's workerd and would be down too;
C, an extra port or forwarding; D and E, which lose ticks; F, at's daemon running jobs as root
outside the service's hardening; and G, the heaviest, which also touches rxmd9's line on Durable
Objects.

**The platform above reaches the clock through the compute product, never the machine**, decided by
the author on 2026-10-24, option a. The thin clock is called with its machine's binding token, which
only the control of the platform beneath holds. The control of the platform above, an app of the one
beneath, submits like any app a delayed message to the compute product of the platform beneath,
"deliver this to me at time T"; the control beneath fulfils it by setting a tick on its own
binding's clock with its own binding token, and at T the tick reaches the app. A message is
delivered only to the app that submitted it. The operation is RFC 49qyg's `submit`, a message to a
queue, given a delivery time, declared in a thin form in the model with samples before code is cut,
RFC fhg6w; the control above calls it with the organization token it already holds, a scaffold until
the issuer's capabilities replace it. In the column of the platform above, `?clock` is then filled
by `Beneath` through the compute product, so RFC btzlt's check two passes. Rejected: binding the
machine beneath to the platform above too, where the platform above reaches the ground below
directly, against RFC 94y0d; and the clock on the organization's machine, an organization's
resource doing the platform's own work, and nothing for an organization with no machine. It is the
only route that keeps the layering: the control above needs no privilege, and every app later gets
the same "wake me at T" from the same product.

### Ledger

Choices made provisionally while the thread runs, read by the author at its end.

- **A tick is delivered on the machine itself**, provisional, chosen by the advisor on 2026-10-24,
  to the deployment through the local entry, never through Cloudflare, so the tick itself is no
  billed request.
- **A tick is authenticated by a secret of its row**, provisional, chosen by the advisor on
  2026-10-24. The control draws a random secret per row as it sets the tick, keeps only its hash,
  and the tick carries it back. The control's tick route reaches the public through the gateway of
  the platform beneath, so an unauthenticated tick would let anyone make the control call the bound
  account.
- **The thin clock keeps its table on the machine's disk**, provisional, chosen by the advisor on
  2026-10-24, where `?clock`'s contract in `model/graph/boundaries.res` says the footing. That holds
  rxmd9's "a driver restarted asks Cloudflare nothing". So in the as-built graph it is a thin
  `?clock`, a scaffold.
- **The clock's contract, `set` and `describe`, and `cancel` if a need is found, is declared in the
  model with samples before code is cut**, provisional, chosen by the advisor on 2026-10-24, RFC
  fhg6w; its fields are proposed as facts before building.
- **Each binding holds at most 10,000 rows**, provisional, chosen by the advisor on 2026-10-24. A
  `set` past that answers `quota_exceeded`.
- **Back-off starts at 1 s, doubles, caps at 5 min, and never gives up**, provisional, chosen by the
  advisor on 2026-10-24, with one exception: when the target deployment no longer exists on the
  machine, the row is deleted and its reason recorded in `describe`'s `last` until then. Otherwise a
  tick knocks forever on a door that is gone.
- **The clock's fields**, provisional, chosen by the advisor on 2026-10-24 as the integrator
  proposed them, with `cancel` left out:
  - an interface `clock`, version 1, authenticated by the binding's token as driver(machine)'s
    other interfaces are;
  - `set`: `id`, a uint53 the setter chooses, unique within its binding, a `set` of the same `id`
    replacing it; `at`, in milliseconds, one past firing at once; `to`, the deployment on this host,
    as the deployments interface names one; `path`, the route a tick goes to; and `secret`, carried
    back as a bearer. It answers `{id}`, or `invalid`, `beyond_host` where `to` is not on this host,
    or `quota_exceeded`;
  - `describe`: every row's `id`, `at`, `to`, `path`, `tries` and `last`, the reason of the latest
    failure where there is one, never its `secret`;
  - a tick is `POST <path>` through the local entry with the deployment's name as its host,
    `Authorization: Bearer <secret>`, and a body of `{"id": <id>}` alone; a row is deleted on a 2xx.
