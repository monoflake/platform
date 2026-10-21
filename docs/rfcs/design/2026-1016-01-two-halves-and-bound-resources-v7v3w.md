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

RFCs 13ixj, zn3u5 and 49qyg give an app three abstractions, and RFCs vuanj and b8f35 the components
beneath them. Worked out with the author on 2026-10-16: where those components run, on whose resources,
and how the platform borrows a vendor's infrastructure without being bound to it. A vendor's
serverless offering is good, but it lets a customer neither use another's resources nor bring their
own; the platform exists to schedule across them.

The shape the discussion has reached so far:

**Layer 0 is a contract, and runs nowhere itself.** The components that keep it are split by whose things
they hold:

| Who                    | Its control                                        | Stands on                                | Holds                                                                                                                                                                                                   |
| ---------------------- | -------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| the platform           | the platform half's, RFC 8lkuv                     | what the platform half stands on         | what spans organizations, known to an organization as two roles: the authority, its existence, allowance, certificate and loans, RFC 7xpd3; and the directory, where its backing is, RFC 4dijn          |
| an organization        | its control, an HTTPS API the platform runs for it | its footing, which the platform gives it | its products' configuration, the extensions it binds and those lent to it, and the records its components keep: its bundle, its backing, the extent's records, each tablet's writer, the clock's leases |
| an organization's apps | --                                                 | its extensions, compute and storage      | its data and what runs it: each database's tablet, the blob's bytes, the sandboxes, its requests in and out                                                                                             |

Worked out with the author on 2026-10-18: the platform and each organization are kept apart the same
way, a control on a footing of its own and what it runs apart from it. The platform's half is the
first row; an organization's half is the other two.

**Whoever controls a resource can see what runs on it.** So nothing that spans organizations is
placed on a resource an organization holds, and an organization that binds a resource others bind
trusts its holder as it trusts a vendor.

**A vendor is borrowed without binding the platform to it.**

- **Every edge to a vendor is a contract the platform writes**, in its own terms -- an object store
  that reads back at once what was written, a database in SQLite's dialect, a runtime, a timer --
  and a vendor's name appears only in the binding that keeps it. What one vendor alone offers is
  never what correctness rests on.
- **The platform's own state is kept in its own formats in its footing**, RFC b8f35, a database
  that is ground: changing the vendor beneath it is a planned stop, `docs/scope.md`, which every
  organization's data plane runs through.
- **The platform can always be stood up again** from its source and the state it keeps, on a new
  account, by the operator.

**A platform may stand on another, one code as more than one deployment**, RFC 94y0d; what follows
holds of each.

**A control is an HTTPS API, and nothing else**, worked out with the author on 2026-10-18. There
are two: **the platform half's**, which runs in no organization and which an organization knows as
the authority, RFC 8lkuv; and **each organization's control**, which the platform runs for it on the
footing it gives it, RFC vr5lw. No name is
reserved: neither is an app, and neither lives in an organization's namespace.

- **What an organization's control accepts it applies itself**, decided by the author on
  2026-10-20: a task of its own, run on its footing's compute, its progress kept in its footing step
  by step, so a control restarted takes the task up where it stopped. It places each deployment,
  fetches its code by its hash from where it was built, deploys it through each driver's
  `deployments`, RFC vr5lw, and reports each target deployed or failed, which `generation` answers,
  `model/contracts/products/generations.res`. No other component deploys an app.

- **An organization's control holds what is that organization's alone**: its products'
  configuration, the deployment of its apps, how its extensions are made into its three products,
  and the records its components keep. It answers that organization's admins, and reaches the
  authority only for what the platform half holds of it, RFC 7xpd3.
- **A client draws, and computes nothing**: every warning, every choice
  offered and whether a warning was dismissed comes from the API, which keeps a dismissal as
  configuration, so every client shows the same and none works it out again; a dashboard may only
  reshape what it is given for display. How a person is authenticated to an organization's control is
  below.
- **A warning is one model, whatever raises it**, worked out with the author on 2026-10-19, and a
  reminder is a warning raised ahead of a date: its kind, a code; what it is about, an id; when it
  was raised; what it says, from the API; whether it may be dismissed; and, once dismissed, the
  dismissal, kept as configuration on what it is about. It stands while its cause holds and is
  cleared when the cause is gone, by whatever finds it, so the API returns the same warnings to
  every client. **Sending one elsewhere, as an email, is a delivery of the same warning**, added
  later. [D14]
- **Everything that serves runs in an organization**, and none of it needs the authority to serve or
  to start: an organization reads its bundle, and reaches the authority only to change it, which
  `model/check.res` checks.

**A control changes what it holds by generations**, worked out with the author on 2026-10-18, alike
in every control and the extensions each binds.

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
- **The configuration API is one set of operations over every kind a control writes**, decided by
  the author on 2026-10-20, `model/contracts/products/generations.res`: `change` a batch of
  records, as a dry run or taken, or going back to a generation; `read` and `list` a kind's
  records, at the current generation or one named; `generations` and `generation`, each with where
  it is deployed; `warnings`, and `dismiss` one. Each kind is a case, so a kind added is a case
  more; making one resource, as a bucket, is a client's to draw. The footing's own tables, a
  `generation` and a `store`, are no kind of it.
- **A record changed names the generation it was read at**, decided by the author on 2026-10-20,
  and the change is refused as `stale` where that record changed since, so two admins changing one
  record never overwrite each other unseen, as a file's write names the hash it saw, RFC 13ixj.
- **A handle is resolved as it is received**, decided by the author on 2026-10-20: wherever an id
  is sent, a handle may stand for it -- a path in the tree, or a name a change gives a record it
  makes -- and the control resolves it to the id then, giving a record made its id at once. A
  handle lasts that one request; nothing past the control sees one, and every component speaks id
  to id.
- **Every record is a row of a kind, an id and the generation that wrote it**, worked out with the
  author on 2026-10-19, in the footing's `configuration` table, RFC b8f35: its `version` and its
  `content`. **A record deleted is a row whose content is empty**, so going back and looking back
  both see that it was. The id is drawn from the one space of its scope's resources, so it names
  one record whatever its kind.
  - **Every kind holds a `description`**, free text and empty unless written, and nothing else in
    common.
  - **A resource is its id; where it is shown is apart**, worked out with the author on
    2026-10-19: an app, a database and a bucket of either type hold no name, and what binds or calls
    one is resolved to its id, so components speak id to id. An organization's resources and folders are
    shown on one tree, so what belongs to one project sits together however its owner likes, and
    nothing bound moves.

    A node is a `tree` record, `model/contracts/records/control.res`: its id the resource's own or
    a folder's, the folder it sits in, its type, its slug and the name shown.

  - **A path is the slugs from the top joined by `/`**, `shop/api`, as a file's path is written,
    RFC 13ixj; never eight hex digits a part, so wherever an id is taken a path may be taken
    instead. **Within a folder a type and a slug are unique together**, the `tree` table's key, so
    an app and a database of one project may share a slug and two apps may not; a path carries no
    type, which a client draws and a command names.
  - **A folder alone holds nodes**, so every part of a path but the last is a folder; it is deleted
    only while empty, from the leaves inward, RFC vuanj. Moving or renaming a node changes its
    `parent` or `slug` and never its id, and is a generation as every change is.
  - **An app's slug is never a scope the gateway reserves**, worked out with the author on
    2026-10-19: `compute`, `storage` and `database` now, a list in the code that only grows as the
    platform offers more, RFC vr5lw; its name shown may be anything.
  - **A record names another by its id alone, never by a name**, so a name changed breaks nothing,
    and what still depends on a record is the rows of the current generation naming its id.
  - **Each generation is a row of its own**: its number, rising within its control; its `time`, by
    the footing's clock, as a lease's is, since no host's is trusted; its **`actor`**, the account or
    app whose capability asked, its `sub`, RFC b8f35; and, where it goes back, the generation it
    `reverts` to.
- **What is compiled is never written**: grants, paths, firewalls and bundles are compiled from what
  is written, and the API offers no way to write them, as RFC vuanj has it of grants.

**Only an organization is a scope, and only an organization holds anything.** It holds the apps,
the buckets, the databases and the resources they run on; the scope of RFC vuanj is an
**organization scope**. A person who wants apps of their own makes an organization, named as they
like.

- **A user account is an id and holds no resource**, its record its own settings alone. Any number of organizations may name it, each as a
  member, who may use what the organization holds, or as an admin, who may also manage it.
  Everything in an organization is visible to every member.

**A person signs in to the platform half, and is a member by their organization's**, worked out
with the author on 2026-10-18. The platform half keeps accounts and nothing of what an organization
does; an organization keeps who its members are and nothing of how they sign in. Trust is handed
down a layer at a time, each holding its own range alone.

- **Signing in gives an account credential**, short-lived, signed by the authority and naming the
  account alone, RFC 7xpd3. An organization's control checks it by the platform's public key,
  without reaching the platform, checks the account against its own members, and its issuer signs
  the capabilities a member or an admin is given. Past that, both controls take capabilities alone,
  as every component does, so a person, an app's code and the controls of a platform above are
  checked alike.
- **The authority lost, no one signs in anew**: a credential already given serves until it expires,
  and every organization goes on running.
- **Who holds a thing is told by who may change it**, worked out with the author on 2026-10-19:
  what an owner changes as it likes, touching no one else, is the owner's own record; what is unique
  across owners is the platform half's; and what the platform alone decides of an owner is the
  authority's record of it.

  | Of an organization                         | Is                 | Kept                                                        |
  | ------------------------------------------ | ------------------ | ----------------------------------------------------------- |
  | `name`, `description`, `security`, `grace` | its own            | its own control's `configuration`, kind `organization`      |
  | each member and its role                   | its own            | its own control's `configuration`, kind `member`            |
  | each invitation not yet accepted           | its own            | its own control's `configuration`, kind `invitation`        |
  | each resource's name shown and its folder  | its own            | its own footing's `tree` table                              |
  | each app mounted under its gateway         | its own            | its own footing's `scope` table, RFC vr5lw                  |
  | `allowance`, `deleting`                    | the platform's say | the authority's record of it, RFC 7xpd3                     |
  | its status and where its backing is        | the platform's say | the authority's record and the directory, RFCs 7xpd3, 4dijn |
  | its label                                  | unique             | the platform half's                                         |
  | its certificate                            | compiled           | no record                                                   |

  What is its own is `model/contracts/records/control.res`; what is the platform's say,
  `model/contracts/records/platform.res`. **An account is an id to an organization**, known by the
  credential it holds and nothing of its own record.
  - **A username and a label are written alike**, worked out with the author on 2026-10-19, since
    either may stand in a domain name: lowercase ASCII letters, digits and the hyphen alone,
    beginning and ending with a letter or a digit, as RFC 1123 has a host's name; never beginning
    `xn--`, punycode's; of 3 to 16 characters, as many as an extension or a name shown, and only ever
    raised, well inside the 63 a DNS label holds; and never eight hex digits, which would read as a
    scope's id, RFC vr5lw. A dot would make another level of the name, and an underscore no public
    CA certifies, `docs/lessons/`. Upper case given is lowered.
  - **A name shown is an account's or an organization's `name`**, set as its owner likes in ASCII
    letters of either case, digits, the dot, the underscore, the hyphen, and a space between them,
    never leading, trailing or beside another; at most 16 characters, enough as an extension's 16
    are, RFC vuanj; empty unless written.
  - **A member is written only once it accepts**, worked out with the author on 2026-10-19: an
    admin invites an account, an `invitation` of the organization's own naming the account and the
    role offered, and the account's acceptance writes the `member`, its account and its role,
    `member` or `admin`, and is reported to the platform half, `model/contracts/records/control.res`.
    So no one is put in an organization unasked. An invitation lasts seven days, as a certificate
    does, and is sent again once it lapses.
  - **No username or label is given that the platform reserves**, worked out with the author on
    2026-10-19: one list for both, since either may stand in a domain name, `model/names/reserved.res`,
    merged from the names a site keeps from its users, `vendor/`, the mailboxes RFC 2142 names, and
    the platform's own words and providers. **The list only grows**, and a name added that someone
    holds stays theirs: it keeps the name from whoever would take it next.
  - **Reserved means kept for the platform**, worked out with the author on 2026-10-19: the
    ordinary flow refuses a reserved name to whoever asks, on any platform, and the operator alone
    gives one, by hand, to an organization of the platform's own. The check holds that every label
    the platform's own organizations hold is reserved, so no one takes it first.
  - **`deleting` is when an organization's deletion was asked**, empty unless asked, and emptied as
    it is withdrawn; it is the authority's, which carries it out even with the organization's own
    control gone, RFC b8f35.

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
- **An organization runs nothing until a resource is bound or lent to it.**
- **Every control binds extensions by one piece of code**, worked out with the author on
  2026-10-18. Each holds its own extensions alike --
  each host's binding and its credentials, the binding's quota, levels and grace, the relays and
  private networks its hosts may use, the capacity lists sent to each driver and what each driver
  reports -- so it is written once, here, and runs in every one.
  - **An extension's record is `model/contracts/records/control.res`**, kind `extension`,
    worked out with the author on 2026-10-19: an extension is a host injected from outside, never
    made within, and what is made within binds it. Its record holds where its driver's
    management answers and the binding token, sealed; the levels and place copied from its host as
    it is bound and its own from then; its quota, grace and relays; whether its host is declared to
    have a public address; a management token and a shell key, sealed, where given; and the
    warnings its admin dismissed, a dismissal being configuration.
  - **An organization's `grace` is what its bindings inherit**, a week unless set, RFC vr5lw.
- **A control may lend what it binds, and then manages what it lent and nothing more.** It opens
  a binding of its own host for the borrower, sets its quota, and hands over that binding's token;
  the borrower holds the loan as any binding, by the same code, and reaches the host only within it.
  The lender keeps the host's management token, and with it the host's own configuration -- its
  records, its shell, its grace -- and touches nothing else of the borrower's. A driver is told
  nothing of a loan: it sees one binding more. The platform lends to its organizations. **It is
  named a loan**, decided by the author on 2026-10-20, as a lease is a clock's lock, b8f35.
  - **A loan is a record on either side**, worked out with the author on 2026-10-19: the
    borrower's is an `extension` like any, whose `lender` names who lent it, so its control knows
    the host's management token and shell key are the lender's, never its own, and a client shows
    it lent.
- **Each organization's control stands on its footing; its apps stand on its extensions**, RFC
  vr5lw. Its footing is one compute, one storage and one database the platform gives it, never an
  extension; its extensions give compute, storage and databases, a database only in the platform's
  own contract or made of compute and a volume. The footing's database is in SQLite's dialect, taking atomic batches, at most 10 GB or what
  its vendor's plan holds, which every compute can reach; it is ground, `docs/scope.md`, and 10 GB is a
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
  and how a set composes to one, is RFC vr5lw's.

- **A primitive is whatever keeps its contract**, a vendor's or a product of the platform's own.
- **What stands between an organization's resources and its three products is the platform's**,
  deployed and run by it on those resources, and never shown: an organization sees the three
  products, and, as usage, what the components beneath them cost on its own resources.
  **A platform sells by opening a cell on the platform beneath**, an organization there whose
  products it imports, RFC 94y0d: an organization above has a cell beneath, opened through that
  platform's API, whose products are given it as its footing and as the extensions it buys, and
  what each cell uses is reported. A user account buys nothing, since it holds nothing.

No app calls an app of another organization, RFC 49qyg.

**An organization's requests come in and go out through the resources bound to it**, each through
its driver, RFC vr5lw.

**The platform keeps what spans organizations; each organization's control keeps its own
configuration; its extensions hold its data and run it.**

| Product  | Configuration, the organization's control   | Data, on its extensions                                                                      |
| -------- | ------------------------------------------- | -------------------------------------------------------------------------------------------- |
| storage  | its buckets and their policies              | each file's path and each object, content shared by hash, the extent's packing and splitting |
| database | its databases and their bindings            | the rows, the log, the snapshots                                                             |
| compute  | apps, versions, declarations, bindings, env | what a call leaves behind: a schedule's repeats dropped, a queue's messages                  |

- **Whatever an organization opens is configuration, whoever opens it**: a bucket, a database, an
  app -- by a person through a client, or by an app's own code calling its organization's control at
  run time, RFC zn3u5 -- and an extension bound, through the control that binds it. Data is only what
  lives inside what was opened.
- **Two truths, each changed in one place.** The authority holds each organization's existence,
  allowance and certificate, and what it lends it, RFC 7xpd3; the organization's own control
  holds its products' configuration and its own extensions, and makes its three products of them as
  it likes, which is the organization's business and none of the platform's. The authority lost,
  no organization is added and nothing is lent anew, and nothing else stops: an
  organization's control goes on binding its own extensions and opening what they can hold.
- **Each truth is copied down as a bundle**, numbered by generation and signed in the chain to the
  root. The authority's record gives an organization its certificate, allowance, loans and status,
  pulled when its control holds none and on a notice, RFC 7xpd3; the organization's control compiles its own configuration with it into the
  bundle its components serve from and from nothing else -- its grants, its allowance, its schedules, its
  backing, the policy placement follows. **Both are kept in the organization's footing**, and a
  compute's deployment says only where that is, so a compute that starts reads the newest bundle it
  can verify there, and starts while either control cannot be reached.
- **A secret never enters a bundle**, worked out with the author on 2026-10-18. It is deployed as a
  secret of the one deployment that reads it, and kept by that deployment's host -- on Cloudflare a
  Worker's secret, which that Worker alone reads; on a machine by its driver, beside the deployment
  -- so a start finds it where it runs, and a deployment running a user's code holds its own
  secrets and no other's. A bundle names the secrets a deployment needs, never their values.
  - **What a control must deploy again it keeps sealed** among its records in its footing, under a
    key deployed as a secret of its own deployment, so the footing alone opens nothing: an app's
    secret env, the stores' secrets, the organization's signing key, the scope's salt and key, a
    management token, a shell key.
  - **A secret changed is a deployment of what reads it**, as env is, RFC 49qyg; and a deployment
    can be taken over only by a host it was deployed to beforehand, its secrets with it, since a
    host it never reached waits for its control.
  - **The host that runs a deployment sees its secrets**, as whoever controls a resource sees what
    runs on it, above. Sealing keeps them from whoever holds the data alone -- the footing's vendor,
    a token leaked, a snapshot -- and so keeps the platform beneath from opening the parcels of the
    one above, RFC 94y0d.
- **An organization signs its own capabilities**, with a key of its own that the authority
  certifies for seven days and renews every day, RFC 7xpd3. So an organization runs on its own for at least six
  days while the platform's half cannot be reached, and only its configuration cannot change; the
  platform takes over again when it returns.
- **Each bundle is signed by the control that compiles it**, worked out with the author on
  2026-10-18, as a signed record of RFC b8f35's form: the authority's by its own key in a chain to
  the root, RFC 7xpd3; an organization's by a key its control alone holds, apart from the key its
  issuer signs capabilities with, certified as that one is, for seven days and renewed every day. So a component of the data plane taken over can sign a capability and never a
  configuration.
- **A bundle is kept as CBOR**, its `version` read first, as the workspace's `spec/json.md` has every
  record, with its generation; an organization's names the generation of the platform's it was
  compiled with. **A component refuses a generation lower than one it has read.** Starting cold it knows
  none, so whoever can write the footing could hand it an older bundle still signed: only the
  footing's vendor, trusted as ground, and never past the certificate's seven days.
- **A timer is written into the scheduler of the resource it fires on**, at deployment, as
  configuration -- a vendor's cron, a node's own timer -- so it fires while the platform's half
  cannot be reached. The platform fires a tick itself only where a resource has no scheduler. A tick
  fired on several computes is taken by one, by a lease in the footing. Nothing a timer starts is
  needed for correctness: what waits on time is checked again on the next request as well.
- **An organization's footing may be snapshotted outside it**, to an S3-compatible object store an
  admin names, never one of its own extensions, which a lost footing could no longer find. Each
  snapshot, with the current bundle and the key its control's secrets are sealed under, is sealed
  under a key of its own, and that key is sealed to a
  public key the admin gives, by HPKE, RFC 9180. The private key is the admin's, held offline, so
  nothing the organization runs can open its backups, and with it the organization can read
  everything it holds without the platform.
- **A scope's salt and key are derived in the platform's half**, where the masters are deployed, and
  delivered to the organization's control as its certificate is, which deploys them to the blob
  as secrets, so the masters never leave the platform's
  half while the blob that seals with what they derive runs in the organization's, RFC b8f35.
- **An organization cannot revoke; the operator can, at once.** An organization is held on the
  platform and does not manage it, so its own deletion waits for its certificate to run out, below.
  The operator manages the platform and revokes a user account at once, and what depends on it is
  revoked with it along the graph of dependencies, and nothing else:
  - the user account is removed from every organization it is in, and one it was the last admin of
    is revoked: its certificate is revoked and never renewed;
  - every binding a revoked organization holds ends, and the cells it bought are suspended, RFC
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
