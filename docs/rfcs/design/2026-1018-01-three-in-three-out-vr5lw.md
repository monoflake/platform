---
name: 'Three In, Three Out'
title: "A platform takes compute, storage and a database from beneath and gives compute, storage and databases above, one of each beneath for its control alone and as many as it likes above, every organization's apps standing on the compute and storage it extends"
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFCs v7v3w and 94y0d stand two platforms one on the other, each with a control of its own. Worked out with the author on 2026-10-18: what a platform takes from beneath, what it gives
above, and what each resource can give, so that one platform stands on another as it stands on a
vendor.

The shape the discussion has reached so far:

**The three products are compute, a database and storage**, the names layer 0 shows: compute was
the functions of RFC 49qyg, and storage the store of RFC 13ixj. **A platform takes the same three
from beneath and gives the same three above**; what it adds is the layers between, a cleaner
abstraction and a scheduler free to choose among resources. So a platform stands on another exactly
as it stands on a vendor, RFC 94y0d.

**Compute is of three kinds, the first of two:**

| Kind        | How it runs                                        | Kept between calls       | Kept past a restart |
| ----------- | -------------------------------------------------- | ------------------------ | ------------------- |
| function    | a call at a time: `derive`, or `effect`, RFC 49qyg | nothing                  | nothing             |
| `instance`  | every call for one key reaches one live instance   | its memory, shared       | nothing             |
| `container` | an `instance` with a volume of its own             | its memory and its cache | its volume          |

- **A `container` is an `instance` and a volume**, and mounts nothing but a volume. The volume is
  small as a rule -- an account's login, a client's state -- and what is large goes to storage. It
  takes the place of RFC 49qyg's daemon: a `pool` is several containers that stand in for one
  another, a `keyed` one a container per key.
- **What program a kind runs is apart from the kind**: the sandbox, a V8 isolate, WebAssembly or a
  process, RFC vuanj. A browser or a database engine needs a process; a `derive` always runs in
  WebAssembly.
- **A `container` here is the cloud's**, a process with its own disk, and is bound to no runtime
  such as Docker. The storage's 16 MiB unit of sealed data is a parcel, RFC b8f35, named apart from
  it by the author on 2026-10-18.

**Storage is of two uses, and only one is offered above as it is.**

| Use      | What it is                                                                                         |
| -------- | -------------------------------------------------------------------------------------------------- |
| `object` | the storage's own: buckets of files by path and of objects by hash, RFC 13ixj, in its own protocol |
| `volume` | a disk: bytes changed in place and flushed, mounted by one `container` at a time                   |

- **A volume can give `object`; `object` never gives a volume.** Buckets can be kept on a disk,
  but a disk cannot be made of files written whole, however fast: a database changes a few bytes
  of a file and must have them flushed at once, one writer at a time.
- **`object` is a contract of the platform's own, in a protocol of its own and never S3's**,
  decided by the author on 2026-10-19 in place of the subset of S3 worked out on 2026-10-18:
  `write` an object whole, `read` it whole or by a range, `describe` whether one is there, `delete`
  it and `list` by a prefix, each read seeing every write before it -- what the blob asks, RFC
  vuanj, and no more, in the storage's own words below. Every object is at most 16 MiB. It needs no condition on a
  write, since a parcel is named by its content and a journal's object by a seed drawn at
  random, no rename and no upload in parts. **What takes it and what gives it are one**: a store
  is reached by it, and a platform gives an `opaque` bucket by it, RFC 13ixj, so one platform's
  storage is the next one's `object`, RFC 94y0d.
- **S3 is a bridge wrapped around the platform's own operations, never beneath them**, decided by
  the author on 2026-10-19, for a client that speaks S3. Each request it takes is mapped onto a
  bucket's operation, and every other is refused as S3's `NotImplemented`, never served as nearly
  as it can be:

  | S3's request                                                    | A file bucket                                      | An object bucket                                                  |
  | --------------------------------------------------------------- | -------------------------------------------------- | ----------------------------------------------------------------- |
  | `GetObject`, whole or by a range; `HeadObject`; `ListObjectsV2` | `read`, `describe`, `list`                         | the same                                                          |
  | `PutObject`, whole                                              | `write`, with no 16 MiB bound where it is `packed` | refused: S3's key is the client's, an object's name its content's |
  | `DeleteObject`                                                  | `delete`                                           | refused: an object bucket is written through the platform alone   |
  | any other: uploads in parts, conditions, versions, ACLs, tags   | refused                                            | refused                                                           |

  The bridge runs cases of its own, by an S3 client. A store that speaks S3 taken from beneath, as
  a footing's snapshots are written to, RFC v7v3w, is the bridge the other way: an S3 client
  wrapped as an `object` store, wanted by the author and not yet urgent. [C35]

- **Each is made of what is beneath it**: an `object` store of compute and a volume; a database of
  compute and a volume, below; a bucket of compute, `object` stores and a database, its records'
  home, RFC b8f35.
- **What is extended is `object` and volumes; what is given is `object` and buckets.** A bucket is
  the platform's own and never taken from beneath: a platform above takes the one beneath as
  `object`, through its `opaque` buckets, so nothing is cut or sealed twice, RFC 94y0d.
- **A volume has no interface but the files it holds**: a file system mounted into one container
  alone, kept past a restart, and on a disk once flushed. It is never reached over a network, since
  being mounted by one alone is what keeps a database on it to one writer; storage reached over a
  network is `object`.
- **A database is made of compute and a volume**, a `container`, whose one volume is mounted by it
  alone and so keeps the database to one writer; a vendor's instance, one per key, does the same
  with a store of its own. Some resources give a database already, a small one. **Whatever gives a
  database gives it in the platform's own contract**, SQLite's dialect and atomic batches,
  `docs/scope.md`, never a vendor's.
- **A database is reached by an HTTPS interface of the platform's own, and the least**, worked out
  with the author on 2026-10-18: one statement, or one batch, each SQL with its parameters, answered
  with each statement's rows. No vendor here speaks a common protocol for it -- D1 is reached from a
  Worker, a machine's SQLite is a file -- so every driver adapts whatever is chosen, and the least
  leaves nothing to adapt that the contract forbids. **The interface is the model's subset, never
  WIT**, decided by the author on 2026-10-19, since it is the platform's own, RFC fhg6w:
  `model/contracts/kinds/databases.res`, a value of SQLite's a union tagged by `kind`, its payload in
  `value`, as an app's typed value is written below.
- **Whatever gives a database keeps each minute of its last 30 days and rewinds to any**, decided by
  the author on 2026-10-20, by what it keeps of its own pages, `rewind` in its contract: D1 and a
  Durable Object by their own recovery, a machine by its WAL archived and its volume's snapshots,
  how written with the code. A rewind is slow and rare.
- **Each host's driver declares its databases' limits** -- a statement's size, its parameters, how
  long a query may run -- as it declares its levels: a vendor's in the code, which knows the vendor,
  as D1's from `docs/lessons/`; a machine's from a default the platform gives, which its holder may
  change. The platform holds each database to what is declared of it.

**A typed value is written by its WIT type, in JSON or in CBOR: one model, two forms**, worked out
with the author on 2026-10-18, for an app's calls; the platform's own interfaces, the database's
among them, are the model's subset, RFC fhg6w. How a record at rest is kept is RFC b8f35's and the
bundle's.

- **A value of SQLite's an app passes is a WIT variant**,
  `variant value { null, integer(s64), real(f64), text(string), bytes(list<u8>) }`, its integer
  held within 2^53 either way by the database, which refuses one past it, RFC fhg6w.
- **A name is its owner's**: a user's, of a function, a field, a case or a flag, is written as the
  user wrote it, since changing it changes what they meant; the platform's own interfaces are
  written in `snake_case`, their words whole, neutral and formal, nested by aspect; and so are the
  encoding's own words below.
- **The type is the WIT's, and never written in the value.** Both ends hold the same WIT, checked as
  the call graph is deployed, so a reader parses each value by the type it expects and refuses one
  that does not parse. Only where the WIT leaves which one open -- a variant, a result, a value of
  SQLite's -- is a `kind` written, naming the case, its payload under `value`, and absent when the
  case carries none.

  | WIT                          | JSON                                                                     | CBOR                 |
  | ---------------------------- | ------------------------------------------------------------------------ | -------------------- |
  | `bool`                       | `true`, `false`                                                          | true, false          |
  | `s8` to `s32`, `u8` to `u32` | a number                                                                 | an integer           |
  | `s64`, `u64`                 | a decimal string                                                         | an integer           |
  | `f32`, `f64`                 | a number; `"not_a_number"`, `"positive_infinity"`, `"negative_infinity"` | a float, any of them |
  | `char`, `string`             | a string                                                                 | a text string        |
  | `list<u8>`                   | base64url, unpadded, as the subset's bytes                               | a byte string        |
  | any other `list`, a `tuple`  | an array                                                                 | an array             |
  | `record`                     | an object in its fields' order, an `option` that is none left out        | a map, the same      |
  | `option` elsewhere           | `null`, or the value                                                     | null, or the value   |
  | `enum`                       | its case's name                                                          | its case's name      |
  | `variant`                    | `{"kind": case, "value": payload}`                                       | a map, the same      |
  | `result`                     | `{"kind": "success" or "failure", "value": payload}`                     | a map, the same      |
  | `flags`                      | an array of the names set, in their order                                | an array, the same   |

  Bytes are one text across the platform, decided by the author on 2026-10-19: base64url without
  padding, RFC 4648's fifth section, as the model's subset writes them, RFC fhg6w, so a value read
  from an app's export and from a database is written alike, and fits a URL or a header unescaped.
  An `option` within an `option`, which neither form tells from none, and a resource's handle,
  which means nothing past its process, are refused as they are deployed.

- **Each request chooses its form**, by `Content-Type` and `Accept`, `application/json` or
  `application/cbor`; the platform's components speak CBOR among themselves, and CBOR is what a
  component answers where a request names neither, decided by the author on 2026-10-21, an app's
  own exports choosing for themselves. Both are built in v0, and run one set of examples, each in both forms, which every
  codec must judge alike, `tests/codec/`.
- **A value's hash is the platform's alone, and is of its structure, never its bytes**: values equal
  in structure are one value however they were written, in either form, in any order of a record's
  fields. A caller computes none, and a `derive`'s outputs are cached by it, RFC vuanj.

**Layer 0's operations are named in whole words, neutral and formal**, worked out with the author on
2026-10-18, each product an interface of the platform's own:

| Product  | Operations                                                                                                                              |
| -------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| storage  | on a file or an object `write`, `read`, `describe`, `list`, `delete`; `publish`; a bucket through its organization's control, RFC 13ixj |
| database | `execute`, one statement or several, atomic together, RFC zn3u5                                                                         |
| compute  | an app's own exports; `status`, the one taking an id; `submit`, a message to a queue, RFC 49qyg                                         |

The rights a capability grants stay `read`, `create`, `replace`, `delete`, `alter` and `call`, RFC vuanj, so
a `write` asks `create` where its path is new and `replace` where it is not; and an `effect`'s
outcomes stay `success`, `rejected`, `unavailable` and `unknown`, RFC 49qyg. `put`, `get` and `head`
are S3's and HTTP's, and stay in the S3 bridge above alone.

**Whatever runs is deployed as its configuration is applied, never loaded as a call comes**,
worked out with the author on 2026-10-18. Since opening anything is a change of configuration, RFC
v7v3w, each has a moment it is applied, and a task, which no one waits on in a dashboard, deploys
it then: an app's version, a database's writer, an `object` store made of a volume, a component of the
platform's own. Compute is reached by two operations, deploying code into what is held already --
never a change to a driver's list -- and calling what was deployed. On Cloudflare a deployment is a
Worker of its own, made through the vendor's API; on a machine, an isolate or a process in its
organization's container.

- **A deployment is running or stopped**, and is stopped, resumed or deleted; it is deleted only
  once stopped.
- **What a host holds of them is bounded as its driver declares**, as its levels and its databases'
  limits are: Cloudflare's in the code, a hundred Workers an account on the free plan; a machine's
  from a default its holder may raise or lower, by more than a count -- by how full the machine is.
  [D8] **Each driver declares as well how long a call may run**, Cloudflare's in the code, 10 ms of
  CPU on the free plan and five minutes on the paid; a machine's is a field its driver must
  declare, whose default, and whether it counts CPU or the clock, are open. [D8]
- **A call that opens something waits on that task as any call waits on an outcome**, RFC 49qyg:
  looked up until a deadline, then `unknown` with its id.
- **A new version takes calls once every host of its set holds it**, decided by the author on
  2026-10-20, the bundle's generation moving them over together; where a host's deployment fails,
  the version before serves on, a warning is raised, and the failed target is reported, so the
  admin tries again or goes back. Its migrations run first, as RFC zn3u5 has them.
- **Function, instance and container are deployed by one interface**, `deployments`, decided by the
  author on 2026-10-19 in `model/contracts/kinds/deployments.res`: `deploy`, `stop`, `resume`,
  `describe` and `delete`. **A deployment is of what it runs**: an app, by its id, or a component of
  the platform's own, by the name the model gives it, so neither is renamed. Deploying is
  idempotent -- this version runs, sent again the same -- and carries what no bundle may: the code
  by its hash and where to fetch it, the footing's address, the deployment's secrets, the networks
  it may reach, and on a machine the container it runs in. The rest it reads from its bundle.
- **The three differ in how what is deployed is called**, which is an app's own exports in WIT, RFC
  49qyg, never the platform's subset: a function at `POST {address}/{export}`; an instance at
  `POST {address}/{key}/{export}`, every call for one key delivered to one instance running; a
  container at the one port its image is deployed with, over HTTP. A driver passes a call through
  as it came, and its cases hold that, and that a stopped deployment answers `unavailable`.

**Code is delivered in its sandbox's own form, built by what its target allows, and kept where it
was built**, worked out with the author on 2026-10-18.

- **Each runtime takes one form**: modules, a bundle of JavaScript modules, WebAssembly within it as
  it likes, run by V8; a component, WebAssembly's, run by wasmtime; an image, whose format waits on
  the container [C11], run by an OCI runtime. WIT keeps the types one however it runs, RFC vuanj.
  Each driver declares the runtimes it gives, `model/ground/drivers.res`: Cloudflare's own alone; a
  machine's `workerd`, Cloudflare's runtime under an open license, so one bundle runs alike on both,
  `wasmtime`, and runc, crun and youki. `workerd` is no hardened sandbox and asks for one around it
  where code may be hostile, `docs/lessons/`: on a machine it runs inside its organization's
  container, whose isolation from other bindings is not promised, RFC v7v3w.
- **Form, runtime and isolation are three things**, decided by the author on 2026-10-19, as the three
  layers below have them: the form is what a builder makes; the runtime what runs it; the isolation
  what keeps it apart -- an isolate within its process, the kernel's namespaces and cgroups, and
  later a kernel in user space and a virtual machine, each standing on its own and none above
  another. A runtime stands on a list of isolations, so `workerd` in a container stands on
  `isolate` and `kernel` both. A deployment names its form, the isolations it must stand on, which
  its control asks by what its scope may risk, and a runtime only where it must: unnamed, the
  driver chooses among those that take the form and stand on every isolation asked.
- **Source is the Git provider's, GitHub alone for now**, and the platform keeps no source.
- **What builds is chosen by the target**:

  | Target     | Built by                                                                 |
  | ---------- | ------------------------------------------------------------------------ |
  | Cloudflare | Cloudflare's own builds, GitHub Actions, or the platform's CI once it is |
  | a machine  | GitHub Actions, or the platform's CI once it is                          |

  Built by Cloudflare, the build uploads a version of the Worker and deploys nothing, its deploy
  command changed to do so, `docs/lessons/`, and the driver deploys that version as configuration is
  applied, so a Worker's name and bindings stay configuration's. Built by GitHub Actions, the
  workflow in the user's own repository keeps the artifact among its own and tells the control of
  it by GitHub's OIDC token, which names the repository and the commit.

- **An artifact is kept where it was built, as long as its builder keeps it**: Cloudflare the last
  hundred versions; GitHub Actions ninety days unless set otherwise, up to ninety for a public
  repository and four hundred for a private one, `docs/lessons/`; the platform's CI as it will set.
  [D11] A driver fetches it from there by an address the control asks the builder for, so the
  bytes go past the control.
- **An artifact is built for the one target, sandbox and architecture asked**, and is never shared
  between targets: two targets each build from the source.
- **Another machine, or a return to an older version, takes the artifact while its builder keeps
  it, and builds it again from its commit once it does not.** Built again it may differ, and is
  then a version of its own.
- **The version just replaced can always be returned to**: Cloudflare keeps it, and a machine keeps
  the version it replaced on its own disk until the new one serves.
- **A version's identity is its code's hash**, kept in configuration and checked against whatever
  is fetched, and a `derive`'s outputs are cached by it, RFC vuanj.
- **Running code is kept on its target and started from there, never fetched as it starts**:
  Cloudflare keeps it in the Worker's version; a machine's driver keeps it on the machine's disk, in
  each binding's own share apart from its volumes -- the version running and the one it replaced,
  removed once the new one serves. So a start waits on no builder, no control and no storage, which
  itself runs on compute, and an artifact is fetched once, as it is deployed.
- **Three bounds alone decide whether code is taken**: how large one artifact may be, as each driver
  declares -- Cloudflare's 3 MB on the free plan and 10 MB on the paid, compressed, its global scope
  run within a second, `docs/lessons/`; a machine's from a default its holder may change; how much a
  binding may hold in all, its quota, RFC v7v3w; and how much the machine has free now, as its
  driver reports. A deployment past any of them is refused, naming which.
- **Charging is no part of the platform**, worked out with the author on 2026-10-18: what one
  platform takes as a resource another sells -- one platform's own cloud is the resource of the
  platform above it, and that platform's users' own clouds are theirs -- so what is a cost depends on
  who looks. The platform keeps bounds and reports use, each binding's own; what a vendor charges
  is between it and its account; and what charges on a platform is an app, which reads use through
  the controls' APIs as any client does, and acts through them as its capability allows, bounding
  or suspending an organization.

**Availability and durability are one model, applied to compute, databases and storage alike**,
worked out with the author on 2026-10-18:

| Product  | Availability                                                        | Durability                                                     |
| -------- | ------------------------------------------------------------------- | -------------------------------------------------------------- |
| compute  | how many hosts hold a deployment, and whether one takes over        | none: it keeps nothing                                         |
| storage  | as RFC 13ixj has it                                                 | as RFC 13ixj has it: copies, and the domains they lie apart in |
| database | its writer's, a compute's: its standbys and how fast one takes over | its log's and snapshots', a placement's in storage, RFC v7v3w  |

**The levels are RFC 13ixj's, and mean of a host what they mean of a store**: each host declares its
availability and custody as it is bound, RFC v7v3w, and its custody is `true` only where the
organization alone controls it. **A set may be composed to a level higher than its members'**,
worked out with the author on 2026-10-18, by these rules alone, each met by a level's own
definition:

- **Only members at `stable` or above compose**: what is `opportunistic` may vanish at any moment,
  and what is `best_effort` has no steady environment, so several of either may fail together.

  | Set, each at `stable` or above                                                | Composes to                                                                                       |
  | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
  | a `pool` on 2 hosts or more, on distinct nodes                                | availability `redundant`, any answering while one is lost                                         |
  | a `pool` on 2 hosts or more, in distinct regions                              | availability `multiregion`                                                                        |
  | a `keyed` container or a database's writer on 2 hosts or more, distinct nodes | availability `recoverable` at most: a lease must lapse before another takes over, a while cut off |
  | 2 copies or more, each `persistent` or above, on distinct nodes               | durability `replicated`                                                                           |
  | the same, in distinct zones                                                   | durability `multizone`                                                                            |
  | the same, in distinct regions                                                 | durability `multiregion`                                                                          |

- **A set's level is the higher of its lowest member's own and the highest its spread composes
  to**, its spread being RFC 13ixj's `copies` and `distinct`; so one member that is `multiregion` of
  itself, as Cloudflare's network, is not pulled down, and machines compose as the rules allow. A
  need is asked as a level or as a spread, and the placement solves either.
- **Where a level came from is shown and never compared**: a level is compared as its code alone,
  RFC 13ixj, and the API says whether it was declared or composed, and of what.

- **Everything is placed by one function**: those that meet every need are kept -- the sandbox,
  each capability declared, the levels, the binding's quota, the machine's free space -- and among
  them each is scored by rendezvous over its weight, as a parcel is among stores, RFC b8f35. So a
  host or a store added or removed moves only what it wins or held.
- **An organization's control places each deployment as configuration is applied**: a set of hosts,
  as many as its availability asks, every one deployed to beforehand, its secrets with it, RFC
  v7v3w, and the set compiled into the bundle and never written. Running, the data plane chooses
  within the set: any host for a `pool`, one held by a lease in the footing for a `keyed` container
  or a database's writer. On Cloudflare the set is one account, which scales a Worker itself.
- **A change is taken only where whatever it touches has a solution**, among what is bound then, and
  a dry run names the need nothing meets. Each item is judged on its own.
- **An item that loses its solution later, by what the platform does not hold -- a resource expired,
  a binding revoked -- is placed again where the rest allows**, since a placement is compiled, and
  is otherwise warned of, the data plane running on with what is left. It stays so until it is
  changed, and a change to it is taken only once it solves; a change to anything else is taken as
  ever. Nothing removed takes another's solution with it, since a removal follows the graph of
  dependencies, RFC v7v3w, and a store goes only while every placement holds without it, RFC 13ixj.

**What each resource gives:**

| Resource                    | Compute                                    | Storage               | Database                                      |
| --------------------------- | ------------------------------------------ | --------------------- | --------------------------------------------- |
| a machine, a VPS or at home | function, `instance`, `container`          | `object` and `volume` | one its driver makes, a container on a volume |
| a Worker                    | function                                   | --                    | --                                            |
| a Durable Object            | `instance`, once metering holds, RFC 94y0d | its own small SQLite  | a small one                                   |
| D1                          | --                                         | --                    | a small one                                   |
| R2                          | --                                         | `object`              | --                                            |

**A footing is one of each, and for a control alone.** It is one compute, one storage and one
database, each meeting one kind of its class at least -- on Cloudflare a Worker's function, R2's
`object` and D1 -- trusted as ideal, `docs/scope.md`. Its compute must give a function, and
`effect` among it, since a control writes and answers an API; it needs no `instance`, keeping its
state in its database alone.

**Every organization is kept so: a control on a footing, and its apps on what it extends**, RFC
v7v3w. Its control stands on one compute, one storage and one database the platform
gives it, and keeps its records there; its apps stand on the compute and storage extended into it,
of any kinds, and databases given in the platform's own contract or made of compute and a volume.
Above, a platform
gives as many of the three as it has organizations to give them through.

**A platform takes nothing from beneath but what a driver gives**, worked out with the author on
2026-10-18. A host -- a machine, or a vendor's account, Cloudflare's as one -- runs one driver, on
itself: on a machine as a process, on an account as what that account runs. One driver gives every
kind its host can, of compute, storage and databases, in the platform's terms; it serves every
binding of it, of any organization on any platform, and keeps them apart, RFC v7v3w; and its own
management it shows to no binding. A platform gives an organization's three products to a platform
above through the same interface, RFC 94y0d, so one platform's output is the next one's input, and
one code is both.

- **A driver manages, and data goes past it.** It opens, lists and ends what it gives, and reports
  usage; for each thing opened it hands back an address, reached by a credential for that thing
  alone that the control made, below, and which speaks the platform's contract -- the vendor's own interface where it already does, an
  adapter the driver deploys beside it where it does not, as a Worker in front of D1, RFC b8f35.
- **A driver holds its host's credentials**, put there by whoever holds the host; a control holds
  none of them for what the driver gives, and takes one only to configure the host, below. Using a driver is trusting that holder, who can read what runs and what a
  database keeps, and remove the driver, which nothing prevents; only what storage keeps is sealed
  against them, RFC b8f35.

**A driver is a component of its vendor's own, made of implementations**, worked out with the author
on 2026-10-19: `driver(machine)` and `driver(cloudflare)`, at layer -2 beside the host they run,
`model/graph/components.res`. Neither does the other's work, since neither vendor has the other's
abstractions. Each holds its management beside its implementations, the process that answers the
management interface below, RFC fhg6w.

- **A kind is a contract, and has no language**: each of the six a resource gives -- function,
  instance, container, object, volume, database, `model/ground/resources.res` -- is declared once by
  the model. **An implementation of a kind has one**: a Worker over R2 and a process over a
  machine's file system both give `object`, on grounds that share nothing, so each is written as its
  ground asks, `model/ground/drivers.res`. A driver implements every kind its vendor's resources
  give and no other: `driver(cloudflare)` function, instance, object and database, in ReScript;
  `driver(machine)` all six, in Rust.
- **Nothing calls an implementation but through its kind's contract**, and no implementation calls
  another, so above the drivers a product speaks of `object` and never of R2 or a disk.
- **One set of cases runs against every implementation of a kind**, at its HTTP API, so the drivers
  are held to one interface. Each kind's contract is an interface of the subset, RFC fhg6w, in
  `model/contracts/`: `object`, `database`, the drivers' management and `deployments`, which function,
  instance and container share, are declared, and each is sampled in `tests/`, decided by the author
  on 2026-10-19.
- **The cases are data in `tests/`, three of a kind**, decided by the author on 2026-10-19:
  `codec/`, a value in JSON beside its CBOR, and inputs every reader refuses; `kinds/`, each
  interface's cases, a case a list of steps -- an operation called, its output or its failure and
  reason expected -- as WebAssembly's `.wast` scripts are; and `properties/`, what no fixed answer
  shows, a history checked by a named checker, as Jepsen's are: one instance for a key, and a read
  seeing every write before it, alone in v0. A step may expect any value with `$any`, keep one with
  `$capture` for a later step's `$use`, and write bytes of a length with `$bytes`, or a text led
  by a statement and filled with spaces with `$text`, a length past a bound among them -- one the
  contract fixes, as an object's 16 MiB, or one each driver declares, as a statement's size, which
  a runner asks the driver under test for [D8] -- so a case past a bound is written once for every
  driver; a case may be `given` the capacity of its kind it starts with; a database's case may be
  held on `copies`, run where a tablet's copies stand on machines, and a step may `lose` some of
  them, RFC vuanj; and a step
  may be answered `within` some milliseconds, called again until it is answered as expected, as
  what a driver makes is made in a while. Each case starts from nothing, and an output expected is
  the whole output.
- **What is deployed in a sample is a fixture**, `tests/fixtures/{name}/fixture.json`, decided by
  the author on 2026-10-19: an app of its own form and exports, an echo or a counter of its key's
  calls, which the runner builds and serves, writing a deploy's version, form and artifact where a
  step names the fixture; one fixture may be another `served` under a hash not its own or from
  nowhere, or `padded` past a bound a driver declares. Its source is the runner's, written with it.
  **A call to what is deployed is a step of its own**, `send`: to an address captured, an export,
  a key for an instance, and a body in the app's own WIT, answered as it was sent or with the
  platform's `stopped`, `model/contracts/subset/calls.res`; the check holds it to its shape alone.
  A deployment's case may be `given` the container it runs in. A form a driver takes no runtime for
  is passed over, the runner asking the driver what it gives [D8]. **A property names its checker,
  the interfaces it is run on, a fixture where it deploys one, and its load**, and the checker is
  the runner's.
- **The check holds the samples to the contracts**, `model/checks/written/cases.res`: each step
  calls an operation that exists, with an input that parses, expecting an output that parses or a
  reason its operation has and the failure that reason is; every operation and every reason of an
  interface sampled is met; and every input a codec sample refuses is refused by the reader the
  check holds. **One runner reads them all**, in `code/tools/`: it takes an address and a
  credential, never an implementation's code, and speaks HTTP itself, so no client hides what an
  implementation answers.

**A driver is managed by a list, and keeps the least it must**, worked out with the author on
2026-10-18. What follows is its management alone; each primitive's contract is above.

- **A binding comes of a token its control makes**, which the host's holder enters in the driver's
  own management, which no binding sees -- a command on a machine, a secret on an account. The
  driver shows it once and keeps it salted and hashed, never the token itself. **A driver never makes a credential of itself**:
  each comes of someone's act, below.
- **A host's levels are declared by its host, and copied by each binding**, availability, durability
  and the rest, RFC 13ixj. A vendor's host is declared in the code, which knows what the vendor is;
  a machine's holder may declare it in its driver, or not. A binding copies what is declared as it
  is made, and may set its own instead; what it holds is its own from then, never following the host
  again, and in force within its own organization or platform alone. Three bindings may hold one
  machine three ways.
- **What a binding asks is a list, and the list names capacity, never what runs in it**: a
  container of so many cores and so much memory, a volume of so many gigabytes, a share of object
  storage. What an organization does within it -- which tablet's writer runs where, which app's code,
  how much of it an app may use -- is its own control's, and never reaches the list, so the list is
  small, a few kilobytes, and changes only when what is extended does.
- **The list holds four kinds, each with its capacity**, decided by the author on 2026-10-19:
  `container`, its cores and memory; `volume`, `object` and `database`, a size each. Function and
  instance are never in it: they are deployed into what it holds, by compute's interface. **Each
  item is a `capacity` record**, decided by the author on 2026-10-19, so the driver diffs by its id,
  drawn from its scope's one space, RFC b8f35, and never renamed, as every resource is its id, RFC
  v7v3w.
- **An item's credential is the control's, as the binding token is**, decided by the author on
  2026-10-19: a random secret of 32 bytes the control makes, its BLAKE3 alone sent in the list, two
  while one replaces the other. The driver makes none and shows none, so a list sent again is the
  same list, its answers can be logged, and a credential is replaced by sending a list.
- **The whole list is sent each time, numbered by generation**; a driver takes a newer one over what
  it holds and drops an older one that comes after. It compares the list with what its host holds,
  which is the truth of what exists, and acts on the difference alone: what runs as asked is left
  as it is, what is missing is made.
- **What the host holds and the list does not is not removed at once.** The driver records when it
  first found it so, and removes it once a grace has passed with it still unasked for; within the
  grace the admin may ask for it again, or end it early, which is the one command apart from the
  list. **The grace is a whole number of seconds from 0 to a year**, 0 removing at once, a week
  unless set: set for the organization, and for each binding either inherited from that or its own.
  It is the organization's control's configuration, sent to the driver as a policy with its own
  generation and kept there, so the driver goes on by the last policy while the control cannot be
  reached.
- **A driver keeps the least state it must**: its credentials, the policy and list it last took,
  and when each difference was first found. Everything else it reads from its host, so a driver
  lost and installed again is whole once its control sends the list again.
- **Its management is an interface of the subset**, `model/contracts/kinds/management.res`: `apply` a
  list, `set_policy` the grace, `describe` what it holds, each item `making`, `made` at an address,
  `failed` for a reason, or `unasked` since a time, and `end` an item the list no longer asks. A
  list older than the one held is dropped and answered with the generation held, never failed;
  what it reports of use is open. [C18] A binding new holds generation 0 of both, and a week's
  grace; a list refused holds nothing of itself; an item carries one credential or two, and names
  itself once; and an item ended goes at once, `tests/kinds/management/`.
- **A machine's driver keeps back only what the machine and the driver need**, worked out with the
  author on 2026-10-19, since most machines a small team brings have 1 or 2 GB, and a driver written
  in Rust takes tens of megabytes. Memory kept back is the machine's own, measured as the
  driver is installed, before anything of the platform's runs, and 64 MiB for the driver; the rest
  is offered, and what runs is held under it by cgroup v2's `memory.max`. No CPU is kept back: all of
  it is offered, and the driver and the system are given precedence by `cpu.weight`, so what runs
  may use every core while they are idle. The machine's holder may set either otherwise. What the
  platform runs on a machine for its organization -- the blob, a tablet's writer -- is that
  organization's use, never kept back.
- **A machine runs NixOS**, worked out with the author on 2026-10-19: its newest stable release,
  with what it runs -- containerd, its runtimes, the tailnet -- from nixpkgs unstable, decided by the
  author on 2026-10-21, by a flake, so what a machine is is one revision and nothing kept
  by hand. It runs four things and no more: containerd, which manages all that runs; the host's
  driver, written in Rust for this system alone, RFC fhg6w, which speaks containerd's own gRPC API by
  the client generated from its protobuf definitions, `containerd-client` in Rust, `docs/lessons/`; the
  tailnet, where the machine joins one; and a small software firewall. Docker is not among them: it
  builds images, which a machine never does.
- **What runs is told apart in three layers**, worked out with the author on 2026-10-19:

  | Layer     | Is                                                                                                                                                    |
  | --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
  | manager   | containerd: what is created, started, stopped and removed, each binding in a containerd namespace of its own                                          |
  | runtime   | for a container, an OCI runtime -- runc, crun or youki, chosen a container at a time; for an isolate, workerd for V8's and wasmtime for WebAssembly's |
  | isolation | native Linux, by namespaces and cgroups, for an OCI runtime; within the process, for an isolate's                                                     |

  **A runtime declares the isolation it stands on as a list**, since an isolate run inside a
  container stands on both, and a kind added later, a virtual machine's, is one more entry.
  **Containerd's namespaces keep bindings apart**, each seeing its own containers and images alone,
  RFC v7v3w. **A container outlives containerd's restart**, its shim its parent, so containerd is
  upgraded without stopping what runs. **workerd and wasmtime run from images, each in a
  container**, decided by the author on 2026-10-21: an isolate runtime is a program of its own in a
  container the driver makes, never inside the driver, whose process holds every binding's
  credentials, and its version is its image's, pinned in the file that builds it. The host gives
  containerd and the OCI runtimes alone. **An image is built by Docker, in CI, for every
  architecture a machine runs**: Docker is a builder, what it makes is an OCI image any OCI runtime
  runs, and no machine holds it. How an image is built for delivery and reaches the driver is
  open, the author said on 2026-10-21: for now each is built and tried locally. **A deployment's
  secrets are files on a tmpfs, mounted read-only into its container**, its configuration naming
  their paths alone, decided by the author on 2026-10-21; the driver keeps each sealed on the
  machine's disk, root's alone, so a container comes back after a reboot. **The seal's key is a file
  the driver makes beside them on first use**, decided by the author on 2026-10-21: what is sealed
  is safe from a copy of the sealed files alone, and the machine itself, and so its cloud vendor, is
  trusted, since no vendor's virtual machine is known to give more; a TPM or a key from the control
  is a `Seal` of its own where one is worth it.

- **A machine goes back two ways, each set on its own**: its system, by the generations of NixOS it
  keeps, upgraded at fixed staggered times so a count of generations stands for about as many
  periods; and its workloads' data, by btrfs snapshots of their volumes, kept so many days. Its
  driver sets both from what the machine's disk holds, and reports them.
- **A machine's disk is two file systems, the host's and the workloads'**: ext4, small, for what
  the host keeps -- the system, the driver's own state -- and btrfs for what runs keeps -- containerd's
  own data moved onto it, and every binding's share -- so a workload that fills its disk never
  reaches the host.
  - **The system's store, `/nix`, is the host's, on ext4**, worked out with the author on
    2026-10-19: what the host holds is a set fixed whatever runs -- NixOS, containerd, the OCI
    runtimes, the driver, the tailnet, the firewall, and bash as its one shell, the author
    said on 2026-10-20, neither fish nor zsh on a server -- and all that grows with use is on
    btrfs, code built for a binding among it. A set measured 1.1 GiB trimmed, `docs/lessons/`.
    Generations share every path an update leaves alone, and only one that moves nixpkgs or a
    library everything links costs a whole set. So **ext4 is 5 GB whatever the disk, and btrfs the
    rest**, decided by the author on 2026-10-20: the current set, the one before it and the one an
    update brings, journald held to 256 MB; the driver collects every generation older than the one
    before the current, and a machine downloads its sets and builds none. **The system is the
    machine driver's `system/`, a NixOS module the root's `flake.nix` gives with the disk's layout
    by disko and a template**, worked out with the author on 2026-10-20: a machine's own flake,
    started from the template, adds its name and what the module's options ask -- `machine.disk`,
    `machine.keys`, `machine.memory`, `machine.tailnet.authKeyFile`, and `monoflake.driver.bindings`, the files of the
    binding tokens its driver takes -- in technical words but where they name the platform, and is
    installed by nixos-anywhere. A secret is a file the machine holds, never text in the Nix store,
    and how it comes there is the holder's.
  - **Every machine swaps to a file behind zswap**, decided by the author on 2026-10-21: neither
    zram nor a partition. The file is in `/data`, a subvolume of its own that no snapshot holds,
    and its size is the platform's, worked from the memory the machine's flake states: 2 GiB up to
    2 GiB of memory, as much as the memory up to 8, half of it beyond, at least 8 and at most 16.
    zswap holds at most a fifth of the memory, compressed by zstd, or by lz4 on a weak processor,
    `machine.swap.compressor`, its coldest written back to the file. A container's secrets are on
    a tmpfs mounted `noswap`, so none reaches the disk; what a container holds in its own memory
    may, since the machine is trusted, and a running container swaps none, its memory and swap
    limits one.
  - **A binding's share is bounded by btrfs's simple quotas**, Linux 6.7 on, through containerd's
    btrfs snapshotter, every image layer and container layer a subvolume: a binding's volumes are
    subvolumes of its own, bind mounted, never Docker's named volumes, and one qgroup above them
    all holds the binding's limit, tried on a machine on 2026-10-20, `docs/lessons/`. A subvolume
    joins a qgroup only when told, and the snapshotter tells none, so the driver assigns a
    container's layer to its binding's qgroup between preparing it and starting it, when nothing is
    written yet, and makes each volume with `-i`.
  - **A binding's images are counted by the driver, not by btrfs**, decided with the author on
    2026-10-20: a layer is shared among bindings, and simple quotas charge it for good to the
    subvolume that unpacked it, so layers are the host's. A layer never changes, so the driver
    measures it once, when it is unpacked; a binding's images are the sum of its images' layers, a
    layer two bindings share counted in each; the driver keeps a binding's images as its deployment
    says, the current one and as many before it, collects the rest, and reports what each binding's
    images hold. A binding's limit is one figure: the driver refuses a pull that would take its
    images past it, and sets the qgroup's limit to what its images leave.
- **What a driver has to tell, it pushes**, as events, each with an id: a difference found, a thing
  removed, a thing that cannot be made. It pushes to each binding's control what is that binding's
  alone; one it could not deliver it pushes again later, and hands back as well with the state a
  control asks it for, so an event is never lost, and its id lets it be taken once. No one polls.
- **Liveness is a heartbeat, and the driver's alone**: small, and its own to pace, or none where the
  host is always reached, as a vendor's account. Whoever needs to know a host is up asks its
  driver's heartbeat, and keeps none of its own.

**A host's own configuration is reached apart from its bindings.** Worked out with the author on
2026-10-18: some of what a host offers is none of compute, storage or databases -- a domain's
records on Cloudflare; a machine's shell configuration, its packages, its reboot -- and is reached
with credentials of their own, three in all:

| Credential       | Made by                                                      | Kept by                                              | Kept apart                                | Over                                                      | Reaches                                                                                  |
| ---------------- | ------------------------------------------------------------ | ---------------------------------------------------- | ----------------------------------------- | --------------------------------------------------------- | ---------------------------------------------------------------------------------------- |
| binding token    | the control                                                  | the host, salted and hashed                          | each sees its own alone                   | the driver's HTTPS                                        | compute, storage and databases                                                           |
| management token | the host: the account on Cloudflare, the holder on a machine | the control                                          | not: each authenticates, all see the same | HTTPS: the vendor's API, or a machine driver's management | the host's own: a domain's records; a machine's shell configuration, packages and reboot |
| shell key        | the control, as a key pair                                   | the machine the public half, the control the private | its own                                   | SSH itself                                                | any command                                                                              |

- **A shell key's public half is installed by one line the control gives**, which fetches it from
  an address of that control's -- over HTTPS, carrying a random part no one can guess -- so the key
  never stands in the machine's command history; once the binding is checked to work, the address
  answers nothing more. The control is trusted already, so fetching from it adds no trust, and a
  key pair made there takes effect only once the machine's holder writes its half.
- **Over HTTPS go named operations alone; any command goes over SSH.** A flaw in the platform's own
  code can then misuse a named operation at worst, never run what it likes on a machine, and SSH
  keeps the handshake and the authentication it is trusted for.
- **A machine driver serves plain HTTP, and TLS is a reverse proxy's**, decided by the author on
  2026-10-21: what the driver writes is its operations, on an address its holder configures; where a
  call must be encrypted -- off the tailnet, or wherever HTTPS is asked above -- a reverse proxy in
  front of it adds TLS in a line, so no certificate is the driver's to keep. Who may reach which
  address of a machine, the driver's and a container's, is open, and written as such where the code
  meets it; the capability comes first, the model of who reaches it after.
- **What a control asks depends on the driver's kind**, and only what the platform uses -- a
  domain's records, a shell -- never the host's whole. Without either a binding still works: what a
  Cloudflare driver opens is reached at the address the vendor gives it free, as a Worker's.

- **A management token or a shell key is the control's configuration**, kept by that control alone, sealed as its
  other secrets are, RFC v7v3w, and never in a bundle, since nothing serving needs it.
- **It is the holder's to give, as often as they like**; two controls given it for one host may
  undo each other's changes, which is the holder's choice, never the platform's to settle.
- **A control changes nothing of a machine's own access unless asked**, in settings of the shell's
  own, worked out with the author on 2026-10-18. It warns, and acts only when told:
  - password logins left on: a warning, and the advice to turn them off;
  - **a key the platform made carries a comment in a format of the platform's own**, which every
    control of every platform knows by its form alone, never checking it further, so the keys
    of that form tell how many controls hold the machine, and are shown as such; the form is
    open [C24];
  - of the keys of no such form, with password logins off: one is taken for the holder's own and
    advised kept; more than one bring a warning that may be dismissed, advising one kept beside the
    platform's; none at all is allowed too, a holder reaching the machine as its provider lets it instead.
    Recognizing a key by its form is for showing, never for trusting.

**A call goes by a path the platform compiles, never one the caller chooses.** Worked out with the
author on 2026-10-18. A network is what reaches itself unaided:

| Network       | Who is in it                                                                                      |
| ------------- | ------------------------------------------------------------------------------------------------- |
| within a host | one host alone: a machine's loopback, containers on one machine, an account's bindings            |
| public        | whatever has an address of its own, IPv4 or IPv6                                                  |
| private       | whatever joined it: Cloudflare's network by a tunnel, a tailnet, a local network, a relay's below |

- **A host in two networks is a jump between them, and a path is networks joined by jumps.**
  Cloudflare's edge is the jump from the public network into its own, so a name it serves reaches a
  machine by the tunnel the machine holds; a machine holding a tunnel and joined to a tailnet is
  the jump by which a Worker reaches the tailnet.
- **An organization's control compiles each call's paths as configuration is applied**, into the
  caller's bundle: every path its networks allow, fewest jumps first, then one off the public
  network first. The caller takes the first that answers, so a jump lost costs time and nothing
  more, and nothing the data plane needs waits on a control. A path across the public network is
  allowed, the capability guarding it as it guards every call.
- **A jump carries what passes encrypted end to end, and ends nothing**: the end called answers
  with its machine's certificate, at a name of its organization's no DNS record publishes, so a
  jump's holder sees who speaks and how much, never what. A jump is a driver's, deployed as an
  adapter is, never a container of its own.
- **Within a host is the platform's to take, since it changes the way and nothing else**: the
  contract and every capability checked are those of the public network, RFC 94y0d.
- **A private network's members are known by what joins them**: Cloudflare's network and a tailnet
  by the drivers that join a host to them; a local network by a test run only when the user asks
  for it, each machine's driver reporting the ranges of its private addresses, an overlay's own
  interface aside, and dialing every machine of the organization's within them. A network is shared
  only where the machine dialed proves itself the organization's, since two networks apart often
  number themselves alike. What a test finds is configuration, the control's to write; until the
  user asks again nothing is tested or changed, and a path that stopped answering is passed over.
- **A host without an address is told so as it is bound**, by whoever binds it, and its driver
  checks it by asking a relay to dial the address back; where they disagree it warns, and changes
  nothing of itself.
- **A host without an address joins a network by a connection it holds out to a relay**,
  Cloudflare's tunnel or a machine with an address of its own: the relay is the jump between that
  network and the public one. **Which relays a host may use is configuration**, chosen as it is
  bound: one or more, or all, the relays among what its organization binds. **It holds a lasting
  connection to every one of them**, costing little while idle, so a caller reaches it through
  whichever is nearest the caller, and the first handshake is always right: no one keeps which
  relay is best. A host answers back by the relay nearest its caller. A relay of Cloudflare's is one
  name its network finds the host behind, `docs/lessons/`.
- **A relay is withdrawn by its organization's control**, from what it observes -- a host's traffic
  spent, say -- as any configuration changes: the new list reaches the host in its bundle, which
  connects to what is new before it drops what is gone, and keeps what stays.
- **A Worker reaches a private network by a binding of its vendor's** into what stands behind a
  tunnel, in beta and free while it is, `docs/lessons/`; where it cannot, its path crosses the public
  network.
- **A tailnet is a host that gives no resource, a network alone.** Its driver runs on any compute
  that gives an `effect` function and holds, as its management token, an OAuth client its user makes
  in Tailscale; for each machine joining it asks Tailscale for a key, tagged and authorized ahead,
  so the driver makes no credential, and the machine's driver joins with it.
  - **The policy file is its user's**: one document, replaced whole, `docs/lessons/`. The driver
    checks that it holds what the organization needs -- the organization's tag, and a grant from
    the tag to itself -- and where it does not warns, showing what to add, a warning that may be
    dismissed; it writes the file only where its user turns that on, and then only over the version
    it read.
  - Tailscale's free plan is for non-commercial use and counts each tagged machine among 50,
    `docs/lessons/`: a user's own plan, chosen by them.
- A vendor's thing without an address of its own, as D1, takes the address of the adapter its
  driver deploys, and needs no relay.

**Who may call is a capability's to say; who can reach is the network's, and kept apart.** Worked
out with the author on 2026-10-18.

- **Each export declares how far it is shown**: within its organization, the default, called by its
  organization's apps with a capability at its deployment's address; or public, which it is
  exactly when a name is bound to it or it is mounted under its organization's gateway. Nothing is
  public that neither reaches. Within an organization an address may still stand on the public
  network, where a path to it crosses it, and every call to it without a capability of its
  organization's is refused.
- **An app has no way in until one is given, and one that nothing reaches is warned of**, worked
  out with the author on 2026-10-19. It is reached in three ways, any of them enough: another app
  binding it and calling it through the binding, RFC 49qyg; mounted under its organization's
  gateway, at a fixed address; or a domain of its own bound to it, as many as it likes. An app
  reached by none of them raises a warning, RFC v7v3w, that it can be reached by nothing, and the
  warning clears as soon as one is given. One reached only by binding is reached as it is meant to
  be, and is not warned of.
- **A machine's driver keeps its firewall**, in software, so no hardware firewall is needed: what
  comes in is let in only at the driver's own port and where a path compiled to the machine crosses
  the public network, so what every caller reaches by a private path is not on the public network at
  all; what goes out, only as each deployment's `network` allows, RFC 49qyg.
- **An app is reached from outside where it can be reached and can be found**, worked out with the
  author on 2026-10-18: reached, by an address of its own or a relay; found, by a name bound to it.
  **An entry is that name and nothing more**: on a machine, a listener its driver deploys beside
  the deployments, as it deploys an adapter, so data still goes past the driver, ends TLS with the
  machine's certificate and hands a request to the deployment its name is bound to; a Worker is its
  own entry. No route table stands beside the names. An entry reads the name alone and carries the rest
  unread, but for one path: while it holds a challenge's id unanswered, a few seconds, it answers
  `/.well-known/monoflake-challenge/{id}` itself, below. It answers unavailable while what the name is
  bound to is down, and never authenticates an app's users.
- **An organization's gateway is its own, never an app**, worked out with the author on
  2026-10-19: every organization has one, part of what the platform gives it, never among its apps
  and configured only through its organization's control, RFC v7v3w. It is bound to the
  organization's platform name and answers by path, `/v{n}/{scope}/...`.
  - **A scope is one the platform reserves, `compute`, `storage` and `database` now, or an app**
    the organization binds to it under a scope of its choosing; for an app it drops the scope and
    hands the app `/v{n}/...`, the rest unread.
  - **An app is mounted by a row of its organization's `scope` table**, worked out with the author
    on 2026-10-19: a scope to the app's id, written as a label is, never one reserved, unique by
    the table's key, `model/contracts/records/control.res`; unmounting is the row deleted. The mount is the gateway's configuration, never
    the app's, since an app may never be mounted, or be reached by a name of its own instead, which
    passes the gateway by.
  - **The version is each scope's own**, an integer written with its `v`: put first, it lets all
    that follows change from one version to the next, and the gateway checks its spelling alone and
    carries it through.
  - **An app under it never holds the root**, so a site, which needs its root, is never built
    there; one is built at a name of the organization's own.
  - **Every answer it gives carries `X-Content-Type-Options: nosniff` and
    `Content-Security-Policy: sandbox`**, but a type exempted, by the storage's rule, RFC 13ixj,
    **and no `Set-Cookie`**, removed whatever the scope: a page there shows and does nothing, an API
    is untouched, since a response's policy reaches only the document made from it, and no cookie is
    set for the domain every organization shares. A name of the organization's own bound to an app
    passes the app's answer as it is.
  - What else it does -- authenticating an app's users, a firewall kept in step in the account it
    runs in -- is to be decided, each on its own. [C30]
- **A name bound to a machine's app is a record DNS only**, pointing at the address its driver
  reports, which it reports again as it changes, so a machine's address being fixed, changing or
  new at each restart is all one. A name of the user's own points at a platform name by a CNAME,
  behind a proxy of their own or not as they choose; the platform binds no domain of a user's
  itself. The two may stand together. A machine without an address is reached through a relay of
  Cloudflare's, above.
- **A name of the organization's own is claimed before it is bound**, worked out with the author on
  2026-10-19. Which organization holds a domain is unique across the platform, since an entry routes
  by `Host`: the platform's `domain` table, a domain to its organization and until when its proof
  holds, RFC v7v3w. What it is bound to is the organization's own, a `name`,
  `model/contracts/records/control.res`: the domain, its target written by type as a binding is, an
  app by its id or the storage, RFC 49qyg, and whether it is the storage's preferred.
  - **Three proofs are tried in order, and the first that holds is enough**, worked out with the
    author on 2026-10-19:
    1. **A TXT record, `_monoflake-challenge.{domain}`, is read first.** It is optional, and every
       proof the platform checks reads it: written once by who keeps the domain's records and left,
       it stands for every claim and every check after, as a site verification of Google's does.
       **Its value is the organization's scope id**, 8 hex digits, as a CNAME's target names it:
       only who keeps the domain's records can write it, so it asks no secret. **It proves its domain
       and every name beneath it**, so one record at `example.com` stands for `api.example.com` and
       the rest.
    2. **A CNAME, followed to its end**: only who keeps a domain's records can point it at
       `{scope-id}.{apps}`, an organization's name by its scope's id, which is never given again.
       One at a label proves nothing, since a label let go may be another's.
    3. **An HTTP challenge, where neither is seen** -- a domain's apex, flattened to addresses, or a
       name behind its own proxy -- so a name already pointed at the platform is proven with no
       change to its records: the platform fetches `/.well-known/monoflake-challenge/{id}` of the
       name, and only the claiming organization's entry, holding that id, answers it, as ACME's HTTP
       challenge proves a name, `docs/lessons/`. An entry takes the path only while it holds an id
       unanswered, a few seconds, and passes it to the app otherwise; an app's own use of a suffix
       minted for this is taken as never. The suffix is minted unregistered, which RFC 8615 asks of
       a new one.
  - **A proof holds at most until the domain's registration expires**, read by RDAP, its
    `expiration` event, from the registry IANA's bootstrap names, `docs/lessons/`. A registry RDAP
    does not reach gives no end, and the proof holds until the domain is let go.
  - **A domain held is locked to its organization** until that organization lets it go, or its
    proof's end passes; only then may another claim it, which clears the first's binding. One held
    past its registration with no end known is the operator's to settle by hand.
  - **Every proof is checked again weekly**, in the same order: the record read, the CNAME looked
    up, the challenge's few seconds.
    One that still holds changes nothing, but its end moves to a registration renewed; one that
    fails raises a warning, RFC v7v3w, unbinds nothing, since a failure may pass and the end is what
    releases, and is checked again the next week. **A registration within 30 days of expiring
    raises a warning** too, which stands until it is renewed.
  - How the platform could hold an organization's DNS, so an apex is pointed by the platform
    itself, is later. [D13]
- **A Worker is public at the address its vendor gives it**, or at a domain its account holds,
  bound in that account.
- **A platform's name may be served from a user's own Cloudflare account**, its traffic counted
  there: where that account holds a domain of its own and the platform holds a management token
  for it, the domain's zone takes the platform's name as a custom hostname, served by a Worker on
  the zone, and the platform, holding its own domain's records, proves the name and points it there,
  DNS only. Its certificate is the vendor's, one for that name, asked of Google's CA so it
  takes nothing of Let's Encrypt's count for the platform's domain; that one is given across accounts,
  the name DNS only, is to be tried. [C26] Where it holds no domain, the vendor's address or the user's own domain serves instead.
  `docs/lessons/`
- **An organization is given one platform name, `{organization}.{apps}`, bound to its gateway**,
  worked out with the author on 2026-10-19: `{apps}` a domain apart from the one every control of
  the platform answers at, which the operator chooses, as a vendor keeps its users' pages off its
  own domain, so nothing an organization's app sets reaches a control or a client of one.
  `*.{organization}.{apps}` is never given: an app is public
  under the gateway or at a name of the organization's own, which the organization holds and binds
  to any of its resources. Which organization holds a label of the domain is the platform
  half's, RFC v7v3w; which app a name of the
  organization's is bound to is its own control's, and a name is bound to one app at a time; a
  label the platform reserves, as `www`, `api` and `status`, is never given, RFC v7v3w.
  - **The domain is asked of the Public Suffix List before the platform opens to the public**,
    which the list asks of a domain's size, `docs/lessons/`. Until then a cookie set for the whole
    domain would reach every organization's, which the gateway's rules alone prevent; that its
    account's holder could change the gateway is accepted while every user is one the author
    invited, so the name points at it DNS only.
  - **`{organization}` is its scope id or any label it holds, all answering alike**, worked out with
    the author on 2026-10-19: a link at the scope id, eight hex digits, RFC b8f35, lasts as long as
    the organization, and one at a label as long as the label is held. **An organization may hold
    several labels at once**, so it moves from one to another with both answering; a label let go
    and taken by another organization breaks the old links and never serves them another's content,
    since the buckets and the hashes are each organization's own, RFC b8f35.
- **An organization's storage answers under its gateway**, at `/v{n}/storage/...`, RFC 13ixj: a
  link answers what a user uploaded, HTML as likely as not, made harmless by the gateway's rules,
  so the storage needs no domain apart from its apps'.
  - **The storage is bound to names as an app is**, the organization's own among them, and one may
    be its preferred, which `publish` answers with, the gateway's where none is. Every name bound
    answers alike, the gateway's always, and every one serves an object in a sandbox, RFC 13ixj.
  - **A name of its own is the organization's to keep**: a change of it reaches what the platform
    holds -- which name `publish` answers with, the configuration naming it -- and never a link handed
    out, hard-coded elsewhere or kept in an app's own data. Since names stand together, a change is
    a name added, made preferred, and the old unbound when the user likes; **unbinding is what
    breaks a link, and is warned of as such**, a preferred name changed is not.
- **A certificate service gives a machine its names' certificate**, worked out with the author on
  2026-10-18: an app like any other, in an organization of the platform's own, which asks a
  public CA by ACME and its DNS challenge -- Google's first, which counts no domain's certificates;
  Let's Encrypt beside it -- and renews and, where its CA allows, revokes.
  - **A key never leaves its machine**: the driver makes it and hands the service a request for a
    certificate, and the service gives back the certificate alone, renewing on the same request
    until the driver makes a new key.
  - **It holds no token able to move a name**: each platform name's `_acme-challenge` is delegated
    by a CNAME to a zone kept for validation alone, and the service holds a token for that zone
    only; the records that point a name stay the platform half's.
  - **A machine serving an organization's gateway is given a certificate for
    `{organization}.{apps}`**, its own key behind it. Its holder could answer for another of the
    organization's names only where that name's traffic reached it, and the platform points the
    names. Let's Encrypt issues one set of names five times a week, so through it an organization
    adds five machines a week at most, `docs/lessons/`.
  - A driver asks for a name's certificate with a capability naming it.

**So one platform is built on another by an organization**, RFC 94y0d: the footing of the platform
above is the three that one organization beneath gives, and its control stands on them alone. An
organization opened above has its footing, and the compute and storage it buys, from a cell the
platform above opens beneath through that platform's API; what else it extends comes from its
users' own clouds.

Open, for the discussion that follows:

- The database's sizes, a small one and a large one, and what each is made of. [C23]
- A machine's own upgrades, staggered and run by its driver, and what carries a workload across them.
  [C32]
