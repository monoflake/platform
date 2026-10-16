---
name: 'Two Halves and Bound Resources'
title: "Layer 0 is a contract kept by two halves: the platform's, on serverless vendors behind contracts it writes itself, and each organization's, on the resources bound to it"
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
| an organization's | the resources bound to it          | that organization's alone: each database's tablet writer, the blob's bytes, the executor's sandboxes, its requests in and out |

**Whoever controls a resource can see what runs on it.** So nothing that spans organizations is
placed on a resource an organization holds, and an organization a resource is shared with trusts its
holder as it trusts a vendor.

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

**Only an organization is a scope, and only an organization holds anything.** It holds the apps,
the datasets, the databases and the resources they run on; the scope of RFC vuanj is an
organization's. A person who wants apps of their own makes an organization, named as they like.

- **A user is an id and holds nothing.** Any number of organizations may name it, each as a member,
  who may use what the organization holds, or as an admin, who may also manage it. Everything in an
  organization is visible to every member.
- The operator never signs in to the console.

**A resource is a place that offers capabilities**: a third-party account, a vendor's or any other
service's, or a node.

- **A resource is held by the first organization it is bound to**, the first time the platform sees
  it anywhere, and stays that organization's whoever bound it: binding it is trusting the
  organization with it. An admin is only who is allowed to act, since a user holds nothing; an admin
  who leaves loses their control of the organization and nothing else.
- **A resource the platform already knows is shared from its holder to another organization**,
  never brought in by a user. A user who is an admin of both makes the share. The organization it is
  shared with may use it; the holder both uses it and manages it.
- **Every quota on a resource is its holder's**, at two levels: how much the resource gives in all,
  set when it is first bound, and how much each share may use of it, set when the share is made.
- **An admin of the holder manages the resource**, and may remove it.
- **An organization has at least one admin.** The last admin leaving is the organization dissolved,
  done only once everything running in it has been removed, from the leaves inward, RFC vuanj.
- **An organization runs nothing until a resource is bound to it or shared with it.** The platform
  lends none of its own.
- **A resource bound to more than one organization keeps them apart as well as the platform can**,
  within a process, and that is not promised.

**The platform sells resources through an organization of its own, reserved for it.** That
organization holds what is sold, and the platform pays the vendor for it and charges for it; it
shares each with a buyer's organization, with a quota. A user buys nothing, since a user holds
nothing.

**The platform's own vendor accounts are never bound to an organization**: they run the platform's
half and nothing else.

No app calls an app of another organization, RFC 49qyg.

**An organization's requests come in and go out through the resources bound to it or shared with
it**: a node's network, or a third-party account, which the platform operates through that account's
API with a credential an admin gives it.

**The platform keeps an organization's configuration and decides for it; the resources bound to the
organization hold its data and run it.**

| What                                                                    | Is                                                    | Half               |
| ----------------------------------------------------------------------- | ----------------------------------------------------- | ------------------ |
| a scope's own tablet, its grants and allowance; each product's settings | configuration                                         | the platform's     |
| the backing                                                             | configuration                                         | the platform's     |
| placement                                                               | deciding                                              | the platform's     |
| the clock's table, and its ticks                                        | configuration and deciding; a tick runs where it goes | the platform's     |
| the extent                                                              | data, written with every put                          | the organization's |

- **The platform's half is not the control plane.** Parts of it serve the data plane -- the issuer,
  placement, the clock -- and go on while the control plane is lost, as every part of the data plane
  does.
- **A configuration's truth is in the platform's half; the organization's half runs from a copy**
  of what it serves by, delivered to it, and reads nothing else. While the platform's half cannot be
  reached, the organization's half goes on from its last copy until the capabilities it holds
  expire, and the platform takes over again when it returns.
- **An account bound to an organization is configured by the platform alone.** Its owner is warned
  that changing it by hand may stop what runs on it working.

**Between resources, a call takes the nearest way**: inline within one account of one vendor; over
a private network laid over the public one, where one can be had; over the public network
otherwise.

Open, for the discussion that follows:

- How long a capability lives, which bounds how long an organization's half runs while the
  platform's cannot be reached, RFC vuanj.
- Where an admin's credential for a third-party account is kept, and what it may do.
- How the operator's allowance, RFC vuanj, relates to the quotas a holder sets on its resources.
- How a buyer's organization is charged for what the platform's reserved organization shares with
  it.
- Which vendor primitives are borrowed, each behind which contract.
- The private network between resources.
