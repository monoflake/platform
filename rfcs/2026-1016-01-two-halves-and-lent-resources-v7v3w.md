---
name: 'Two Halves and Lent Resources'
title: "Layer 0 is a contract kept by two halves: the platform's, on serverless vendors behind contracts it writes itself, and each organization's, on the resources its members lend it"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFCs 13ixj, zn3u5 and 49qyg give an app three abstractions, and RFCs vuanj and b8f35 the parts
beneath them. Worked out with the author on 2026-10-16: where those parts run, on whose resources,
and how the platform borrows a vendor's infrastructure without being bound to it. A vendor's
serverless offering is good, but it lets a customer neither use another's resources nor bring their
own; the platform exists to schedule across them.

The shape the discussion has reached so far:

**Layer 0 is a contract, and runs nowhere itself.** The parts that keep it are split by whose things
they hold:

| Half              | Runs on                            | Holds                                                                                                                         |
| ----------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| the platform's    | the platform's own vendor accounts | what spans organizations: the control plane and the deployer, the issuer and the intermediate, the anchor, the root           |
| an organization's | the resources its members lend     | that organization's alone: each database's tablet writer, the blob's bytes, the executor's sandboxes, its requests in and out |

**A resource holds only what its owner may see**, which is why nothing that spans organizations is
placed on a resource a member lends.

**The platform runs on serverless vendors only.** One now, Cloudflare, taken as the ground and ideal
in v0; others are added later, so that losing one is survived, and not before the platform carries
enough to judge its stability by. A node never runs the platform's half: a machine given both to the
platform and to its users is the problem this avoids.

**A vendor is borrowed without binding the platform to it.**

- **Every edge to a vendor is a contract the platform writes**, in its own terms -- an object store
  with a conditional write, a runtime, a timer -- and a vendor's name appears only in the binding
  that keeps it. What one vendor alone offers is never what correctness rests on.
- **The platform's own state is kept in its own formats on vendors' stores**, through `quorum*`,
  RFC b8f35, so a vendor is added as one more copy while everything runs.
- **The platform can always be stood up again** from its source and the state it keeps, on a new
  account, by the operator.

**The control plane is the platform's half.** It is reached at its own API on the platform's domain,
and stands on the vendor contracts directly, never on layer 0, which it deploys.

**A scope is of two kinds.**

- **An account is a person**: who they are, and the resources they bring -- a third-party account of
  theirs, a vendor's or any other service's, or a node.
- **An organization holds the apps, the datasets and the databases**, and the scope of RFC vuanj is
  an organization's. An app is never an account's: a person who wants apps of their own makes an
  organization, named as they like.
- An account belongs to any number of organizations, and an organization has one account or more.
  **Everything in an organization is visible to every member.** Its admin adds and removes members
  and nothing else, with no privilege over what it holds.
- The operator never signs in to the console.

**An account lends its resources to the organizations it belongs to, and to no other**, so whoever
owns a resource sees on it only what they may already see as a member. A member is removed only once
nothing in the organization uses what they lent: that use is removed first. No app calls an app of
another organization, RFC 49qyg.

**An organization's requests come in and go out through its own resources**: a node's network, or a
member's third-party account, which the platform operates through that account's API with a
credential the member gives it.

**Between resources, a call takes the nearest way**: inline within one account of one vendor; over
a private network laid over the public one, where one can be had; over the public network
otherwise.

Open, for the discussion that follows:

- Which half each part not named above belongs to: a scope's own tablet, the backing, the extent,
  the clock, placement.
- Whether the platform lends resources of its own to organizations, or an organization runs nothing
  until a member lends it something.
- Where a member's credential for a third-party account is kept, and what it may do.
- How organizations sharing one lent resource are kept apart.
- What an allowance limits once an organization runs on what its members lend.
- Which vendor primitives are borrowed, each behind which contract.
- The private network between resources.
