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

| Half              | Runs on                            | Holds                                                                                                                                                                                        |
| ----------------- | ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the platform's    | the platform's own vendor accounts | what spans organizations, and what is decided for each: the control plane and the deployer, every configuration's truth, the credentials, the intermediate, the anchor, the root             |
| an organization's | the resources bound to it          | that organization's alone, its data and what runs it: its issuer, placement, the clock's ticks, the extent, each database's tablet, the blob's bytes, the sandboxes, its requests in and out |

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
**organization scope**. A person who wants apps of their own makes an organization, named as they
like.

- **A user account is an id and holds nothing.** Any number of organizations may name it, each as a
  member, who may use what the organization holds, or as an admin, who may also manage it.
  Everything in an organization is visible to every member.
- The operator never signs in to the console.

**A resource is a place that offers capabilities**: a third-party account, a vendor's or any other
service's, or a node.

- **A resource is held by the first organization it is bound to**, the first time the platform sees
  it anywhere, and stays that organization's whoever bound it: binding it is trusting the
  organization with it. An admin is only who is allowed to act, since a user account holds nothing;
  an admin who leaves loses their control of the organization and nothing else.
- **A resource the platform already knows is shared from its holder to another organization**,
  never brought in by a user account. One that is an admin of both makes the share. The organization
  it is shared with may use it; the holder both uses it and manages it.
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
shares each with a buyer's organization, with a quota. A user account buys nothing, since it holds
nothing.

**The platform's own vendor accounts are never bound to an organization**: they run the platform's
half and nothing else.

No app calls an app of another organization, RFC 49qyg.

**An organization's requests come in and go out through the resources bound to it or shared with
it**: a node's network, or a third-party account, which the platform operates through that account's
API with a credential an admin gives it.

**The platform keeps an organization's configuration; the resources bound to the organization hold
its data and run it.** What the platform keeps is small: text, a few keys, and the credentials it
operates third-party accounts with.

| Product  | Configuration, the platform's half          | Data, the organization's half                                                         |
| -------- | ------------------------------------------- | ------------------------------------------------------------------------------------- |
| storage  | its datasets and their policies             | each file's name and hash, content shared by hash, the extent's packing and splitting |
| database | its databases and their bindings            | the rows, the log, the snapshots                                                      |
| function | apps, versions, declarations, bindings, env | what a call leaves behind: a schedule's repeats dropped, a queue's messages           |

- **A configuration's truth is in the platform's half, and is changed there alone.** A read-only
  copy is delivered to the organization, which serves from it and from nothing else: its grants,
  its allowance, its schedules, the policy placement follows.
- **An organization signs its own capabilities**, with a key of its own that the intermediate
  certifies for one week and that is renewed every week. So an organization runs on its own for up
  to a week while the platform's half cannot be reached, and only its configuration cannot change;
  the platform takes over again when it returns.
- **An organization cannot revoke; the operator can, at once.** An organization is held on the
  platform and does not manage it, so its own deletion waits for its certificate to run out, below.
  The operator manages the platform: revoking a user account, the operator revokes its
  organization's certificate at once, never renews it, and removes the user account and the
  organization.
- **An organization is deleted on request, at the end of its certificate.** The last admin leaving
  asks for it once everything in the organization has been removed and stopped, from the leaves
  inward, RFC vuanj; it is carried out when the current certificate runs out, within seven days, and
  the request may be withdrawn until then.
- **An account bound to an organization is configured by the platform alone.** Its owner is warned
  that changing it by hand may stop what runs on it working. Such a change cannot be prevented; v0
  assumes none is made, and finding one afterwards is for later.

**Between resources, a call takes the nearest way**: inline within one account of one vendor; over
a private network laid over the public one, where one can be had; over the public network
otherwise.

Open, for the discussion that follows:

- How a revocation at once reaches what checks capabilities locally, since a chain is checked
  against the root's public key and the platform is never asked. Proposed: every share to the
  organization withdrawn from the copies its holders run from, and what the platform deployed on the
  organization's own resources removed through the credentials it holds.
- What becomes of the other organizations a revoked user account belongs to, among them one it is
  the last admin of.
- How the issuer's standing capability to read every scope's grants, RFC b8f35, changes now that each
  organization signs its own.
- Where an admin's credential for a third-party account is kept, and what it may do.
- How the operator's allowance, RFC vuanj, relates to the quotas a holder sets on its resources.
- How a buyer's organization is charged for what the platform's reserved organization shares with
  it.
- Which vendor primitives are borrowed, each behind which contract.
- The private network between resources.
