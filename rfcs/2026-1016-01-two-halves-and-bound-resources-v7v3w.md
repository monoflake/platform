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

| Who                    | Its control                                        | Stands on                                | Holds                                                                                                                                                                                                        |
| ---------------------- | -------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| the platform           | its control, an HTTPS API in no organization       | the platform's footing, from beneath     | what spans organizations: the accounts, each organization's existence, allowance and certificate, the extensions it binds and what it leases of them, the deployer, the intermediate, the anchor, the root   |
| an organization        | its control, an HTTPS API the platform runs for it | its footing, which the platform gives it | its products' configuration, the extensions it binds and those leased to it, and the records its parts keep: its bundle, its backing, the extent's records, each tablet's writer and log, the clock's leases |
| an organization's apps | --                                                 | its extensions, compute and storage      | its data and what runs it: each database's tablet, the blob's bytes, the sandboxes, its requests in and out                                                                                                  |

Worked out with the author on 2026-10-18: the platform and each organization are kept apart the same
way, a control on a footing of its own and what it runs apart from it. The platform's half is the
first row; an organization's half is the other two.

**Whoever controls a resource can see what runs on it.** So nothing that spans organizations is
placed on a resource an organization holds, and an organization that binds a resource others bind
trusts its holder as it trusts a vendor.

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

**A control is an HTTPS API, and nothing else**, worked out with the author on 2026-10-18. There
are two: **the platform's control**, the platform's half, which runs in no organization and stands on
the platform's footing alone, from the layer beneath, `scope.md`; and **each organization's
control**, which the platform runs for it on the footing it gives it, RFC vr5lw. No name is
reserved: neither is an app, and neither lives in an organization's namespace.

- **The platform's control holds what no one organization can.** It sees every organization -- the
  anchor, the names unique across them, the accounts that sign in -- holds the platform's secrets,
  the masters and the intermediate key, and acts on organizations: opening, suspending, deleting and
  revoking one, setting its allowance, certifying its key, leasing it what it binds. Its privilege is
  where it stands, never a permission granted: only it reaches the platform's footing, and the
  secrets are deployed to it alone, `?source`. On the platform beneath, it is an ordinary client:
  the external platform's control opens its shadows on the internal one as any admin would.
- **An organization's control holds what is that organization's alone**: its products'
  configuration, the deployment of its apps, how its extensions are made into its three products,
  and the records its parts keep. It answers that organization's admins, and reaches the platform's
  control only for what the platform holds of it.
- **The console is a dashboard, an ordinary app in an ordinary organization**, which is named
  `console` by being opened first and holds no privilege: whatever it does it does through the two
  APIs, with the credential of whoever uses it. The APIs are what is kept; a dashboard, a client or
  neither is for later. **A dashboard draws, and computes nothing**: every warning, every choice
  offered and whether a warning was dismissed comes from the API, which keeps a dismissal as
  configuration, so every client shows the same and none works it out again; a dashboard may only
  reshape what it is given for display. How a person is authenticated to either API is below.
- **Everything that serves runs in an organization**, and none of it needs the platform's control to
  serve or to start: an organization reads its bundle, and reaches the platform's control only to
  change it, which `model/check.ts` checks.

**A control changes what it holds by generations**, worked out with the author on 2026-10-18, alike
in the platform's control, an organization's and the extensions each binds.

- **Each change accepted is a generation**: one record changed, or a batch of them changed together
  or not at all. It is checked against the whole of what the control holds, so nothing still
  depended on is removed, RFC vuanj, and once accepted it is compiled and deployed of itself; no
  draft is kept.
- **Asked as a dry run, a change is compiled and not taken**: the API answers with what it would
  change and the warnings it would raise, so a client shows a change before it is made and works
  none of it out.
- **Generations are kept**, and going back is a change of its own, an older generation's records
  given again.
- **Accepted and deployed are told apart**: the API reports a generation accepted, and deployed
  wherever it goes as each driver or bundle reports it.
- **What is compiled is never written**: grants, paths, firewalls and bundles are compiled from what
  is written, and the API offers no way to write them, as RFC vuanj has it of grants.

**Only an organization is a scope, and only an organization holds anything.** It holds the apps,
the datasets, the databases and the resources they run on; the scope of RFC vuanj is an
**organization scope**. A person who wants apps of their own makes an organization, named as they
like.

- **A user account is an id and holds nothing.** Any number of organizations may name it, each as a
  member, who may use what the organization holds, or as an admin, who may also manage it.
  Everything in an organization is visible to every member.
- The operator never signs in to the console.

**A person signs in to the platform's control, and is a member by their organization's**, worked
out with the author on 2026-10-18. The platform keeps accounts and nothing of what an organization
does; an organization keeps who its members are and nothing of how they sign in. Trust is handed
down a layer at a time, each holding its own range alone.

- **Signing in gives an account credential**, short-lived, signed by the platform's control and
  naming the account alone. An organization's control checks it by the platform's public key,
  without reaching the platform, checks the account against its own members, and its issuer signs
  the capabilities a member or an admin is given. Past that, both controls take capabilities alone,
  as every part does, so a person, an app's code and the external platform's control are checked
  alike.
- **The platform's control lost, no one signs in anew**: a credential already given serves until it
  expires, and every organization goes on running.
- **An account signs in by any of the ways it holds**: a passkey; GitHub, Google or Apple; a link
  sent by email; a password; a TOTP code. A password is one way among them and never required, so an
  account may hold none. The platform may later sign people in to others' apps itself, by OAuth.
  [D10]
- **An account sets how many of its ways a sign-in asks, and fewer than two is warned of, never
  dismissed**: the warning is the platform's control's, given by its API with whether it may be
  dismissed, so a client draws it and decides nothing, as a dashboard does above.

**A resource is a place that offers capabilities**: a third-party account, a vendor's or any other
service's, or a node.

- **An admin may change their organization's configuration, and nothing more.**
- **A resource is bound by whoever holds its credential, and may be bound by many organizations**,
  each binding its own, on any platform. Nothing is shared from one organization to another. A
  vendor's primitive is reached through an adapter that speaks its terms in the platform's; a
  machine through its driver.
- **A quota is the binding's**, set by the organization that binds, and none unless set, whether
  the resource is a third party's, the user's own or bought. Ending a binding is the binding
  organization's alone, by the graph of dependencies, as any deletion.
- **A machine runs one driver, and the one driver serves every binding of it**, RFC vr5lw. It keeps
  them apart itself: each binding sees and acts on only its own -- the containers, instances and
  volumes it made, the functions it runs -- and is told nothing of another's. To every binding it
  reports the machine's totals truly -- its CPU, its memory, its network in and out -- and of what
  is counted by binding only that binding's own, the rest as other. A function runs in an isolate
  or a WebAssembly runtime of its binding's own, an instance in a container without a volume, and a
  container in a container with one.
- **A driver sees everything on its machine**, so an organization binding a machine others bind
  trusts the driver's holder as it trusts a vendor. What it stores is sealed, RFC b8f35, and no
  driver reads it; what it runs runs in that machine's memory, kept apart from other bindings as
  well as the technology allows, which is not promised. The platform warns of it as such a binding
  is made.
- **An organization has at least one admin.** The last admin leaving is the organization dissolved,
  done only once everything running in it has been removed, from the leaves inward, RFC vuanj.
- **An organization runs nothing until a resource is bound or leased to it.**
- **Both controls bind extensions, by one piece of code**, worked out with the author on
  2026-10-18. The platform's control and each organization's hold their own extensions alike --
  each host's binding and its credentials, the binding's quota, levels and grace, the relays and
  private networks its hosts may use, the capacity lists sent to each driver and what each driver
  reports -- so it is written once and runs in both.
- **A control may lease what it binds, and then manages what it leased and nothing more.** It opens
  a binding of its own host for the lessee, sets its quota, and hands over that binding's token;
  the lessee holds the lease as any binding, by the same code, and reaches the host only within it.
  The lessor keeps the host's management token, and with it the host's own configuration -- its
  records, its shell, its grace -- and touches nothing else of the lessee's. A driver is told
  nothing of a lease: it sees one binding more. The platform leases to its organizations.
- **Each organization's control stands on its footing; its apps stand on its extensions**, RFC
  vr5lw. Its footing is one compute, one storage and one database the platform gives it, never an
  extension; its extensions give compute, storage and databases, a database only in the platform's
  own contract or made of compute and a volume. The footing's database is in SQLite's dialect, taking atomic batches, at most 10 GB or what
  its vendor's plan holds, which every compute can reach; it is ground, `scope.md`, and 10 GB is a
  hard limit, so an organization that outgrows it is split into several. What runs on extensions is
  made redundant by the placements, RFC 13ixj, and repaired.
- **Choosing is two-sided: a resource says what it is, and what uses it says what it needs.**
  What an extension is, its binding holds as copied from its host or set for itself, RFC vr5lw, and
  the platform places on it only what it
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
  **A platform sells by opening a shadow organization on the platform beneath.** An organization the
  external platform opens has a shadow on the internal one, opened through the internal platform's
  control's API, whose products are given it as its footing and as the extensions it buys, RFC 94y0d;
  what each shadow uses is reported, and charged by an app, RFC vr5lw. A user account buys nothing, since it holds
  nothing.

**The platform's own vendor accounts hold its footing and the footings it gives its organizations**,
and are never bound as an extension.

No app calls an app of another organization, RFC 49qyg.

**An organization's requests come in and go out through the resources bound to it**, each through
its driver, RFC vr5lw.

**The platform keeps what spans organizations; each organization's control keeps its own
configuration; its extensions hold its data and run it.**

| Product  | Configuration, the organization's control   | Data, on its extensions                                                               |
| -------- | ------------------------------------------- | ------------------------------------------------------------------------------------- |
| storage  | its datasets and their policies             | each file's name and hash, content shared by hash, the extent's packing and splitting |
| database | its databases and their bindings            | the rows, the log, the snapshots                                                      |
| compute  | apps, versions, declarations, bindings, env | what a call leaves behind: a schedule's repeats dropped, a queue's messages           |

- **Whatever an organization opens is configuration, whoever opens it**: a dataset, a database, an
  app -- by a person through the console, or by an app's own code calling its organization's control at
  run time, RFC zn3u5 -- and an extension bound, through the control that binds it. Data is only what
  lives inside what was opened.
- **Two truths, each changed in one place.** The platform's control holds each organization's
  existence, allowance and certificate, and what it leases it; the organization's own control
  holds its products' configuration and its own extensions, and makes its three products of them as
  it likes, which is the organization's business and none of the platform's. The platform's control
  lost, no organization is added and nothing is leased anew, and nothing else stops: an
  organization's control goes on binding its own extensions and opening what they can hold.
- **Each truth is copied down as a bundle**, numbered by generation and signed in the chain to the
  root. The platform's gives an organization its certificate, allowance and leases, each day
  and on a change; the organization's control compiles its own configuration with it into the
  bundle its parts serve from and from nothing else -- its grants, its allowance, its schedules, its
  backing, the policy placement follows. **Both are kept in the organization's footing**, and a
  compute's deployment says only where that is, so a compute that starts reads the newest bundle it
  can verify there, and starts while either control cannot be reached.
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
  - every binding a revoked organization holds ends, and the shadows it bought are suspended, RFC
    94y0d; no other organization depends on it, since nothing is shared;
  - the platform stops managing a revoked organization's own accounts and leaves them as they are:
    what runs there is between their owner and the vendor, and nothing is cleaned up on purpose.
- **An organization is deleted on request, at the end of its certificate.** The last admin leaving
  asks for it once everything in the organization has been removed and stopped, from the leaves
  inward, RFC vuanj; it is carried out when the current certificate runs out, within seven days, and
  the request may be withdrawn until then.
- **A host bound to an organization is configured by its driver alone.** Its holder is warned that
  changing it by hand may stop what runs on it working. Such a change cannot be prevented; s0
  assumes none is made, and finding one afterwards is for later.

**Between resources, a call goes by a path of networks joined by jumps**, RFC vr5lw.

Open, for the discussion that follows:

- How a host is bound: what credential its driver gives a binding, and how an admin enters it. [C3]
- What the app that charges reads of use, and how it acts on an organization. [D1]
- How a bundle's secrets are sealed in the footing, and where the key a compute opens them with is
  kept, beside its deployment. [B4]
- What a compute's levels mean, and what a function or a database's writer asks of one. [B19]
- Which ways of signing in each step builds, and what sends an email's link. [C27]
- What one way counts for among a sign-in's factors, a passkey among them, and how an account that
  lost every way it held is given back. [C28]
