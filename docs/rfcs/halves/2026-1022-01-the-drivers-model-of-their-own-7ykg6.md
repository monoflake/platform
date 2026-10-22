---
name: "The Drivers' Model of Their Own"
title: 'The drivers moved to `monoflake/driver`, with a model of their own that fills the roles this one declares'
status: accepted
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The drivers were written here, their kinds' code beside the libraries and the components, and this
model held every detail of them: each implementation's language, what of others' it takes, the
runtimes it gives. A driver is what a vendor gives the platform through a kind's contract, and
nothing above the contract reads how it is built. Where do the drivers live, and how much of them
does this model hold.

## Decision

Decided by the author on 2026-10-22.

- **The drivers live in `monoflake/driver`**, a repository of their own, MIT OR Apache-2.0 as this
  one is: `machine/` and, once it has code, `cloudflare/`. What was written here, the machine's
  management and its container kind, moves there.
- **Three models, each holding its own side of a boundary**: this one what the public platform is
  and what it asks of a driver; `monoflake/driver`'s what each driver is made of; cloud's the hosted
  platform, RFC 8lkuv. A model holds what it provides and exports, never how another is joined
  inside.
- **This model keeps the contracts and declares each driver a role**: every kind's contract and its
  samples stay here, since the products call through them, and `driver(cloudflare)` and
  `driver(machine)` become provided roles, as `authority` and `directory` are, each naming what the
  platform asks of it -- the grounds it stands on, the kinds it gives at their contracts' versions,
  the runtimes and the isolation each stands on. Its check passes alone, a role unfilled.
- **The driver's model holds its blocks and fills the roles**: each implementation, its management
  and the `driver-machine` program, their languages, what of others' each takes and which of this
  repository's libraries each uses, checked, briefed and accepted there by this model's own code,
  which it links as cloud does.
- **The whole is whoever holds all three**: cloud's whole check runs this model with both fills,
  cloud's and the driver's. The dependency runs one way: the driver reads this model, this model
  never reads the driver, and cloud reads both.
- **Until releases cross repositories, a driver reaches this one by path**, the sibling checkout
  `../platform`, as the workspace places them; how the three pin one another's releases is open.
