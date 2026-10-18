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

| Half              | Runs on                            | Holds                                                                                                                                                                                                     |
| ----------------- | ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the platform's    | the platform's own vendor accounts | what spans organizations, and what is decided for each: the control plane and the deployer, every configuration's truth, the credentials, the intermediate, the anchor, the root                          |
| an organization's | the resources bound to it          | that organization's alone, its data and what runs it: its footing, its issuer, placement, the clock's ticks, the extent, each database's tablet, the blob's bytes, the sandboxes, its requests in and out |

**Whoever controls a resource can see what runs on it.** So nothing that spans organizations is
placed on a resource an organization holds, and an organization a resource is shared with trusts its
holder as it trusts a vendor.

**The platform's half runs on serverless vendors only.** One now, Cloudflare, taken as the ground
and ideal in s0; others may be added later, as extensions or beneath the footing's contract, and not
before the platform carries enough to judge its stability by. A node never runs the platform's half:
a machine given both to the platform and to its users is the problem this avoids.

**A vendor is borrowed without binding the platform to it.**

- **Every edge to a vendor is a contract the platform writes**, in its own terms -- an object store
  that reads back at once what was written, a database in SQLite's dialect, a runtime, a timer --
  and a vendor's name appears only in the binding that keeps it. What one vendor alone offers is
  never what correctness rests on.
- **The platform's own state is kept in its own formats in its footing**, RFC b8f35, a database
  that is ground: changing the vendor beneath it is a planned stop, `scope.md`, which every
  organization's data plane runs through.
- **The platform can always be stood up again** from its source and the state it keeps, on a new
  account, by the operator.

**The platform runs as two deployments of one code**, an internal platform on third-party vendors
and an external platform standing on it, RFC 94y0d; what follows holds of each.

**The control plane is the platform's half.** It is reached at its own API on the platform's domain,
and stands on the vendor contracts directly, never on layer 0, which it deploys.

**The platform's half is no organization and runs no layer 0.** A footing and a highly available
compute on the platform's own accounts are all it needs to work, and it stops there: it holds no
store, since what it keeps -- configuration's truth, the anchor, the credentials, the bundles --
fits its footing, and an app's code goes from the deployer to its organization's own blob. It shares
libraries with the organizations and never a part, RFC vuanj, and the operator configures it,
`?source`. **Everything that serves runs in an organization**, the console's among them, and none of
it needs the platform's half to serve or to start: an organization reads its bundle, and reaches the
platform's half only to change it, which `model/check.ts` checks.

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
- **An admin may change their organization's configuration, and nothing more.** That is the one
  real rule; what follows on sharing either comes from it or is a limit set against abuse.
- **A resource the platform already knows is shared from its holder to another organization**,
  never brought in by a user account. The organization it is shared with may use it; the holder both
  uses it and manages it.
- **A share is made by one who is an admin of both organizations.** The real rule asks less; this is
  set against abuse, so that no holder is asked again and again for what it holds.
- **A share is ended by either side alone**, each changing only its own configuration: the holder
  withdraws it, and the organization it was shared with gives it up.
- **The holder withdraws a share by the graph of dependencies while someone can follow it.** When an
  admin of the holder is also an admin of the organization it is shared with, what depends on the
  share there is removed first, as for any deletion. When none is, the holder withdraws it at once,
  and what depends on it is stopped as in a revocation: a holder is never held by an organization
  none of its admins can act in.
- **The organization a share was made to gives it up by the graph of dependencies**, since its
  admins can follow it: it is refused while something of its own depends on the share, which is
  removed first.
- **Every quota on a resource is its holder's**, at two levels: how much the resource gives in all,
  set when it is first bound, and how much each share may use of it, set when the share is made.
- **An admin of the holder manages the resource**, and may remove it.
- **An organization has at least one admin.** The last admin leaving is the organization dissolved,
  done only once everything running in it has been removed, from the leaves inward, RFC vuanj.
- **An organization runs nothing until a resource is bound to it or shared with it.** The platform
  lends none of its own.
- **An organization stands on one footing and on extensions.** Its footing is one database in
  SQLite's dialect, taking atomic batches, at most 10 GB or what its vendor's plan holds,
  `scope.md`, which every compute of the organization can reach.
  It is ground, `scope.md`: the platform makes nothing in it redundant, and its owner is warned to
  bring one that is, which the platform cannot check. 10 GB is a hard limit, and an organization
  that outgrows it is split into several. Everything else bound is an extension -- a compute, of
  which at least one must be, and a store, of which at least one must be before the storage or a
  database holds anything -- trusted as no footing is: what runs on extensions is made redundant by
  the placements, RFC 13ixj, and repaired.
- **Choosing is two-sided: a resource says what it is, and what uses it says what it needs.**
  Whoever binds an extension declares it as it is bound, and the platform places on it only what it
  meets, solving each need against what is bound, never by a resource's name. Every attribute is
  ordered, RFC 13ixj.

  | Declared by | Availability | Durability | Custody | node, site, account, zone, region | Offers                   |
  | ----------- | ------------ | ---------- | ------- | --------------------------------- | ------------------------ |
  | a store     | yes          | yes        | yes     | yes                               | --                       |
  | a compute   | yes          | none held  | yes     | yes                               | its sandboxes, RFC 49qyg |

  A database is no third kind: what it needs splits into a compute for its writer and a placement
  for its log's archive and snapshots, each solved as the rest are. What a compute's levels mean,
  and what a function or a database asks of one, is to be decided. [B19]

- **A primitive is whatever keeps its contract**, a vendor's or a product of the platform's own.
- **What stands between an organization's resources and its three products is the platform's**,
  deployed and run by it on those resources, and never shown: an organization sees the three
  products, and, as usage, what the parts beneath them cost on its own resources.
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

- **Whatever an organization opens is configuration, whoever opens it**: a dataset, a database, an
  app, a resource bound -- by a person in the console, or by an app's own code calling the
  configuration API at run time, RFC zn3u5. Data is only what lives inside what was opened.
- **A configuration's truth is in the platform's half, and is changed there alone.** A read-only
  copy is delivered to the organization, which serves from it and from nothing else: its grants,
  its allowance, its schedules, the policy placement follows.
- **The copy is a bundle**: the organization's configuration compiled into one dense table, with its
  certificate and its backing, numbered by generation and signed in the chain to the root. One is
  issued each day, with the certificate, and whenever the configuration changes: the platform says a
  change is ready, and the organization fetches it. **A bundle is kept in the organization's
  footing**, and a compute's deployment says only where the footing is, so a compute that starts
  reads the newest bundle it can verify there, and starts while the platform's half cannot be
  reached.
- **An organization signs its own capabilities**, with a key of its own that the intermediate
  certifies for seven days and renews every day. So an organization runs on its own for at least six
  days while the platform's half cannot be reached, and only its configuration cannot change; the
  platform takes over again when it returns.
- **A timer is written into the scheduler of the resource it fires on**, at deployment, as
  configuration -- a vendor's cron, a node's own timer -- so it fires while the platform's half
  cannot be reached. The platform fires a tick itself only where a resource has no scheduler. A tick
  fired on several computes is taken by one, by a lease in the footing. Nothing a timer starts is
  needed for correctness: what waits on time is checked again on the next request as well.
- **An organization's footing may be snapshotted outside it**, to an S3-compatible object store an
  admin names, never one of its own extensions, which a lost footing could no longer find. Each
  snapshot, with the current bundle, is sealed under a key of its own, and that key is sealed to a
  public key the admin gives, by HPKE, RFC 9180. The private key is the admin's, held offline, so
  nothing the organization runs can open its backups, and with it the organization can read
  everything it holds without the platform.
- **A scope's salt and key are derived in the platform's half**, where the masters are deployed, and
  delivered to the organization as its certificate is, so the masters never leave the platform's
  half while the blob that seals with what they derive runs in the organization's, RFC b8f35.
- **An organization cannot revoke; the operator can, at once.** An organization is held on the
  platform and does not manage it, so its own deletion waits for its certificate to run out, below.
  The operator manages the platform and revokes a user account at once, and what depends on it is
  revoked with it along the graph of dependencies, and nothing else:
  - the user account is removed from every organization it is in, and one it was the last admin of
    is revoked: its certificate is revoked and never renewed;
  - every share a revoked organization receives is withdrawn, the resources the platform sold it
    among them, from the copies their holders run from;
  - every share it gives is withdrawn, and in every other organization what depends on a withdrawn
    share is revoked with it -- one app of four, when one alone depends on it. Such an app is
    stopped, never removed: what of it was placed on the withdrawn resource stays there, unmanaged
    and unscheduled, and nothing is deleted, so the platform loses no data; getting it back is
    between that organization and the resource's owner;
  - the platform stops managing a revoked organization's own accounts and leaves them as they are:
    what runs there is between their owner and the vendor, and nothing is cleaned up on purpose.
- **An organization is deleted on request, at the end of its certificate.** The last admin leaving
  asks for it once everything in the organization has been removed and stopped, from the leaves
  inward, RFC vuanj; it is carried out when the current certificate runs out, within seven days, and
  the request may be withdrawn until then.
- **An account bound to an organization is configured by the platform alone.** Its owner is warned
  that changing it by hand may stop what runs on it working. Such a change cannot be prevented; s0
  assumes none is made, and finding one afterwards is for later.

**Between resources, a call takes the nearest way**: inline within one account of one vendor; over
a private network laid over the public one, where one can be had; over the public network
otherwise.

Open, for the discussion that follows:

- Where an admin's credential for a third-party account is kept, and what it may do. [C3]
- How the operator's allowance, RFC vuanj, relates to the quotas a holder sets on its resources.
  [D1]
- How a buyer's organization is charged for what the platform's reserved organization shares with
  it. [D1]
- Which vendor primitives are borrowed, each behind which contract. [B5]
- How a bundle's secrets are sealed in the footing, and where the key a compute opens them with is
  kept, beside its deployment. [B4]
- The private network between resources. [C5]
- What a compute's levels mean, and what a function or a database's writer asks of one. [B19]
