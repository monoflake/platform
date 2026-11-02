---
name: 'Five Components Under Products'
title: 'The storage, the database and functions are built side by side from five components -- scope, issuer, tablet, blob and executor -- and never from one another, so nothing beneath an app depends on itself'
status: landed
supersedes: []
blocked-by: []
commits:
  - monoflake/platform@72a7c0d7
  - monoflake/platform@87cee8b5
  - monoflake/platform@269d17f9
  - monoflake/platform@e2d53237
  - monoflake/platform@89e484a7
  - monoflake/platform@4c3b3b97
  - monoflake/platform@2a85ad49
  - monoflake/platform@fe1d3618
references:
  - url: https://developers.cloudflare.com/d1/reference/time-travel/
    took: "every implementation of a tablet keeping each minute of its last 30 days, D1's Time Travel"
  - url: https://blog.cloudflare.com/durable-objects-easy-fast-correct-choose-three/
    took: 'a Durable Object one instance for its id, so one replaced writes nothing after'
  - url: https://developers.cloudflare.com/d1/best-practices/import-export-data/
    took: "what a vendor's export loses, so a snapshot is the platform's own dump"
  - url: https://www.sqlite.org/wal.html
    took: "SQLite's WAL frames, which a machine tablet's copies carry"
  - url: https://developers.cloudflare.com/workers/platform/limits/
    took: 'a request bounded by plan, so content of any size is put by an upload'
---

## Question

RFCs 13ixj, zn3u5 and 49qyg settled what an app sees: a storage, databases and functions.
Working one layer further down with the author on 2026-10-15, each seemed to need the others -- the
storage's metadata a database, a database a file in the storage, a function's cache both -- and
a platform that depends on itself is the problem this design began from. The question is what the
products are made of, and in what order, one layer only: where each component runs is layer -2's.
Names are chosen for what they mean, apart from the names the platform uses now; a clash is settled
when this lands.

The shape the discussion has reached so far, to be decided once it is diffed against what exists:

## Decision

**Layers are numbered from the platform's face, layer 0**, upward to what users build and downward
to what the platform is made of:

| Layer     | What it is                                                                 |
| --------- | -------------------------------------------------------------------------- |
| +1 and up | Users' apps, the platform's own among them, each an app like any other     |
| 0         | The products an app sees: the storage, databases and functions             |
| -1        | The components the products are made of, this RFC                          |
| -2        | What the components stand on: backings, the extent and hosts, RFC b8f35    |
| -3        | The directory, the one global state, the platform half's, RFC b8f35        |
| -4        | The root, which depends on nothing and everything needs, RFC b8f35         |
| ground    | Each owner's footing, one database, and the vendors' primitives, RFC b8f35 |

**The platform runs on itself wherever an ordinary owner could.** What the platform runs is of
three kinds:

- **What an ordinary scope's permissions are enough for**, a dashboard among them, is deployed in
  an organization of the platform's that holds no privilege, down the path every owner takes. It may
  be given a larger allowance, which is a value, not a privilege.
- **What needs a privilege no owner holds**, reaching across scopes, never shares the owners' path,
  so nothing on that path has to tell a privileged request from another, or can let one leak. It
  runs apart, beneath that path: the platform half, which an organization knows as the authority and
  the directory, in no organization, RFC 8lkuv.
- **The components at layer -1 and below**, which keep the platform up and place what owners run. They
  are no app, and are never placed among apps.

This holds only while the graph is clean: nothing the platform needs to start, restart or come back
stands on what it runs as an owner.

**The cycle came from drawing one layer where there are two.** Beneath the products are components, each
smaller than any product, and **the three products stand side by side on the components and never on
one another**. A product that looks like another -- a database's name pointing at an id, a
file's path pointing at a hash -- shares a pattern with it, never a dependency.

| Component  | What it is                                                         |
| ---------- | ------------------------------------------------------------------ |
| `scope`    | Whose data this is: an opaque id, its status, what it may use      |
| `issuer`   | Signs the capabilities every other component checks                |
| `tablet`   | One small SQLite with one writer: SQL, and an atomic batch         |
| `blob`     | Bytes by the hash of their content: put, get, delete               |
| `executor` | Runs a function's code on an input, in the sandbox its kind allows |

**A scope is a concept, never a process**, decided by the author on 2026-10-20: an id, its status
and its allowance, each read from the organization's bundle by whatever needs it, through one
library so every reader judges alike. A process answering them would only read again what its caller
already holds, the bundle in the footing, and add a hop to every call; its status reaches the
organization by the authority's record, RFC 4dijn, and its allowance in the bundle's issuer
section, and how soon either is seen is the bundle's, C36. The other four in the table run.

**A component knows a scope and never a user.** A scope is an organization's, RFC v7v3w; accounts and
logins are above; which user owns
which scope is not a component's to know. Every tablet and every blob belongs to exactly one scope and
never crosses it, so a product with a fault cannot reach another scope, a scope's usage is counted
where it is kept, and a scope is deleted whole. A scope's salt and key, and the stores its bytes go
to, are its physical half, the backing at layer -2 -- RFC b8f35 -- which the blob reads downward;
the salt and key are derived from a master secret and the scope's id, so neither is stored; and
since its key can always be derived again, a scope is never deleted by losing its key, only by
deleting its bytes.

**A scope is deleted one of two ways.** Its owner deletes what it holds from the leaves inward, as
the graph of dependencies orders it -- the apps first, then the buckets and databases they were
bound to, then the scope -- and nothing is deleted while something depends on it, RFC 49qyg; only
then may the owner close their account, which is above. The operator, revoking an owner, stops at
once everything it holds and deletes nothing, RFC v7v3w: a privilege of the platform's, never an
owner's. A scope so suspended is deleted after seven days unless it is restored, RFC b8f35.

**No component trusts its caller: it checks a capability.** A capability names a scope, a resource, an
operation and when it expires, and is signed by the issuer alone, through a chain components verify
with the root's public key and never call at run time -- RFC b8f35. **A request to the issuer is
signed by its caller**, decided by the author on 2026-10-20: the call whole, a COSE Sign1 under the
key of the caller's certificate, RFC fhg6w, which the issuer checks to the root as any component
checks a capability, so what asks is proven the same way on every vendor and never by the
transport. A call is given only the
capabilities its app's bindings allow, for that call alone, and passes them down: a product checks
the resource -- a bucket, whether writes are allowed -- and a component checks the scope. The issuer is
its own component, reading each scope's grants from its organization's bundle, in the footing, RFC
v7v3w. Authenticating the
people who use an app is another matter, above. Decided by the author on 2026-10-20:

- **A call's capabilities are kept by the compute for its app and resource**, asked again as they
  near their expiry, and **each call is given those its bindings allow alone**: what "for that call
  alone" holds is what is passed, never how often the issuer signs.
- **A component's own work -- a sweep, a tablet's archive -- is given a capability by who its
  certificate says it is**, no app asking, reaching its own blob space alone; the blob and the extent
  reach the scope's stores by calls their certificates sign, and no capability, RFC b8f35.

**The operations are six, each a right of its own**: read; create, which is refused where what it
would write already exists; replace, which overwrites what exists and so can lose it as a deletion
can; delete; alter, a database's schema; and call, an export of an app, added with the author on
2026-10-19 since calling is none of the five done to data. Create apart from replace makes a holder that can only
add -- a backup, an audit log -- which, taken over, cannot erase. A database's capability grants
read, create, replace, delete and alter together, RFC zn3u5.

**A scope also holds its `allowance`: what it may use and how much**, in the vocabulary of
capabilities RFC 49qyg declares needs in. It reaches the organization in its bundle as the rest of
its configuration does, RFC v7v3w, and the issuer reads it there; setting it is the control plane's
to do, but what it sets is read here, below layer 0, where every product can find it. **An allowance is the
platform's, though it lives in the scope**: the operator sets it and the owner never does, and one
scope given more than another holds no privilege the other lacks.

**Beside it, a scope holds its `grants`: what each app in it may reach**, an app, a resource and
the operations, a row each. **Their format is the issuer's**, defined at this layer, and the issuer
reads nothing else to decide what a call is given. An app's bindings are configuration, kept in the
platform's half, RFC v7v3w; a deployment compiles the grants they come to into the bundle, in the
issuer's format, and the new version takes a call only once its organization holds that bundle. The
grants are derived from the bindings and never written otherwise, so what an app may reach is
decided in one place, and the function product changes how it keeps bindings without anything
beneath it changing. Grants are written as the control plane works,
at deployment, and read as the data plane works, on each call. **A grant is no record**, decided
by the author on 2026-10-19: what is compiled is never written, RFC v7v3w, so a binding changed is a
generation, the bundle compiled again with the grants it comes to, and the app's version untouched;
the grant's format is declared with the bundle's.

**Inside a scope each product has its own blob space**, since what counts the references to a hash
is the product's own tablet; two products sharing one would delete what the other still holds. **A
call names its space** -- the storage's, the compute's or the database's -- and is held to its scope's
capability alone, decided by the author on 2026-10-20: a product at fault reaches only its own
scope, as above, so nothing past the scope is asked of it.

**The storage** reads its buckets and their policies from the bundle, and keeps one tablet per
scope for the rest of its metadata -- each path's hash, each object, each
hash's size, references and strictest policy, each directory's size -- and
its content in its blob space. A write puts the bytes first and then changes the tablet in one
batch, so a fault leaves at most bytes nothing names, which a sweep removes, and never a name
without its bytes. A hash nothing names is marked and removed later, never in the write.

**A tablet is its implementation's SQLite, and its history is the implementation's own**, decided
by the author on 2026-10-20. Its one writer runs each batch there, and **a write is done once the
implementation has confirmed it**; nothing of it is written again to be kept. A history kept as
pages, never as statements replayed, holds what was written whatever wrote it -- a random value,
the time -- so no input is refused and no write costs twice. From there the rest follows:

- **Returning to an earlier time** is the implementation's own: **every one keeps each minute of
  the last 30 days and rewinds to any**, D1's Time Travel, a Durable Object's recovery, and a
  machine's WAL archived with its volume's snapshots, `model/contracts/kinds/databases.res`. It
  takes a while, and is rare.
- **Past 30 days nothing is kept unless asked**: a database may keep snapshots by tiers, each
  sparser as it grows older, its `retention`, none unless set, RFC zn3u5; and snapshots kept apart
  from its implementation, so it outlives losing a vendor, only where its `copies` and `placement`
  ask, RFC zn3u5. A database moved from one implementation to another goes by a snapshot taken then.
- **A snapshot is the platform's own logical dump, one form on every implementation**, decided by
  the author on 2026-10-20: the schema in its order, `user_version` and `sqlite_sequence`, and each
  table's rows by rowid, each value a `database-value`, so it restores into any implementation and
  keeps what a vendor's export loses -- a hidden rowid, a virtual table, an integer past 52 bits,
  `docs/lessons/cloudflare.md`. **Every snapshot is whole**, written as a file into a `packed`
  bucket, never an `opaque` one, so the storage deduplicates and compresses what two hold alike, and
  each restores alone. **What dumps never stops what writes, where it can**: a machine snapshots its
  volume, at once, and dumps that copy; a Durable Object and D1 serve one request at a time, so
  their dump holds them for its length, taken at a quiet hour and skipped where no batch was
  written since the last. Its format is declared with its code.
- **A read copy** is its implementation's, where one offers it: D1's replicas, read by a session's
  bookmark, and a machine's copies of its WAL; the cursor a write returns is the implementation's
  own.
- **A batch's id and expiry** are written in the tablet's own system table in the same transaction
  as the batch, so whether one was applied is answered exactly, and an expired one is refused.
- **A tablet's one writer is held by whatever gives it**, decided by the author on 2026-10-20. A
  Durable Object is one instance for its id, its uniqueness enforced as it touches its storage, so
  one replaced can write nothing after; D1 runs every write on its one primary; neither keeps a row
  of the footing for its writer, `docs/lessons/cloudflare.md`. **On machines a tablet is its
  copies**, each a SQLite on a volume one container mounts, each on a machine of its own, one unless
  its owner asks for more, as data in the storage is, and at most 5.
- **On machines a write is done once a majority of the copies configured hold it**, decided by the
  author on 2026-10-20: of n, n halved and one more -- 1 of 1, 2 of 2, 2 of 3, 3 of 4, 3 of 5 --
  each having flushed the batch's WAL frames, its primary among them; the rest catch up after. A
  copy checkpoints only what is done, so a frame never done can still be cut.
- **A primary handed over is fenced by its generation.** The footing's `writer` row names each such
  tablet's copies, its primary and its generation. When a majority of the copies has heard nothing
  from the primary for a lease, one raises the generation by one conditional statement and has a
  majority take it; the old primary then gathers no majority and writes nothing more, and the new
  starts from the longest WAL among them, which holds every write done, since two majorities share a
  copy. The lease is the copies' own, never a row of the footing: it dates when a takeover may
  begin, and never decides whether a write is safe. A copy is replaced the same way, one at a time,
  and counted once it has caught up. With one copy nothing is handed over: its machine lost, the
  database is unavailable until it returns.
- **Fewer than a majority alive, a database is read-only**, decided by the author on 2026-10-20.
  Its writes fail as `read_only`; its reads go on from what the copies alive hold, each marked as
  possibly behind, since a write done may lie on the copies lost alone; a warning stands, RFC
  v7v3w. With a majority back, it writes again. The majority is always of the copies configured,
  never of those alive, so a database never writes on fewer than its owner asked.
- **The lock is released by its owner alone, by configuring copies those alive are a majority
  of**, decided by the author on 2026-10-20: from 2 alive, 2 or 3, `model/contracts/records/database.res`,
  shown in a dry run as possibly losing what the lost copies alone held, and never done by the
  platform itself. A configuration short of copies is reached this way alone, never made from
  nothing: it writes again, stands in a warning, and the placement makes the copies it lacks.
- **Where a writer runs is placed at run time**, since a database may be created at any time, never
  only at a deployment. What places it promises at least one writer and never exactly one: two may
  run for a moment, and the vendor, or the generation a majority of the copies took, refuses all but
  one.

**A `transactional` database is a tablet**, and the product adds what an app sees: a directory of
names, ids, the one app each belongs to and whether read copies are on, which is configuration and
read from the bundle. A capability
covers the databases of one app, so a database created for it is reachable once the organization
holds the bundle that records it, RFC v7v3w.

**A function's** code is kept where it was built, RFC vr5lw, its hash its identity, and handed to
its hosts as it is deployed, never fetched by the executor as a call comes; its declarations
are configuration, read from the bundle, and a deployment checks the types and the call graph,
the calls never crossing a scope since they never cross an owner; its calls, their ids,
outcomes and expiry, in a tablet `status(id)` reads; its `derive` cache as a tablet indexing a
code's hash and an input's hash to an output kept in blobs, since a blob's hash is its content's and
cannot be chosen; its queues' messages and its schedules' repeats in tablets, the queues and
schedules themselves being configuration, in the bundle. **The executor stores nothing**: it is given
the code's hash, the input and a sandbox -- for `derive` nothing at all, no capability, network, true
time or randomness; for `effect` the call's capabilities and the network -- and gives back the output
or a panic. Decided by the author on 2026-10-20: **a `derive`'s fuel is its declaration's, passed
with each call**, metered on Cloudflare as C15 settles; **a panic is a reason -- fuel run out, a
trap, memory past its bound -- and a message**; and **an input and an output cross as bytes, the CBOR
of a WIT value**, RFC vr5lw, since a call must pass between JSON and CBOR knowing nothing past itself,
and a WIT value's two forms are told apart by its type alone, which the compute holds and the
executor never reads.

**The executor runs code in one of two sandboxes, a V8 isolate or WebAssembly.**

| Kind     | V8 isolate                          | WebAssembly                            |
| -------- | ----------------------------------- | -------------------------------------- |
| `derive` | never: its budget cannot be counted | **always**, its budget counted in fuel |
| `effect` | yes                                 | yes                                    |

- **A `derive` runs in WebAssembly, which follows from what layer 0 asks of it** rather than from a
  taste: a module that imports nothing can reach nothing, so purity is held by what it lacks, and
  fuel counts instructions, so the same input runs out at the same place on every machine. Any
  language that runs in WebAssembly may be a `derive`, JavaScript built into a component among them.
- **WIT is the one contract** however a function runs: a component's interface is WIT already, and a
  function in V8 is given bindings made from it, so the types checked at deployment never depend on
  the sandbox.
- **A container is open**, kept for what exports `effect` functions from a process held open, such
  as a browser, RFC 49qyg's daemons. Until it is settled, `icmp` is something no sandbox can give.
- **The executor decides which sandbox a call needs and hands it to a host**, layer -2, RFC b8f35,
  one that offers that sandbox and every capability declared; what the hosts offer is what running
  checks a declaration against. Code is deployed before any call reaches it, as its configuration
  is applied, and never fetched as a call comes, RFC vr5lw.

**What the products ask of the components:**

- A tablet runs SQL and atomic batches; returns a cursor with every write; keeps read copies and
  answers a read with a cursor no older than it; returns to an earlier time; archives itself to its
  blob space; and records each batch's id with its expiry, refusing one that has expired, so an
  outcome can always be found. Every capability past the first is used only where a product needs
  it.
- A blob puts bytes with a placement and answers their hash, gets them whole or by range, raises a
  hash to a stricter placement, deletes, and lists, for a sweep alone. **Content of any size is put
  by an upload**, decided by the author on 2026-10-20, since a request is bounded -- 100 to 500 MB on
  Cloudflare by plan -- and one that drops starts again: begun, appended to in order a part at a
  time, each part at most 16 MiB and cut, named and sealed as it arrives, and finished. Each answer
  says how much was received and how much is durable, to the end of the last whole piece, sealed
  and named; a dropped upload is resumed from what is durable, an append beginning anywhere but at
  what was received refused. An upload is held by one instance, as a tablet's writer is; one taken
  up again reads back what is durable to hash it anew, since a content's id is BLAKE3 over the whole
  and no hasher's state is kept. Finishing cuts the last piece and records the content, then seen;
  one left a day expires, the sweep's grace, and its pieces go as any nothing names. A get is by
  range, 16 MiB at most, and an upload's parts follow in order, since cutting and hashing do. Below that face it encrypts
  with the scope's key, lays the bytes out as the placement asks, and places each parcel among
  the scope's stores: each store a parcel may go to is scored by a hash of the parcel and the
  store, and it goes to the highest, RFC b8f35 -- so anyone with the same stores finds the same
  places, more copies take the next in line and leave the first where they are, and a store added or
  removed moves only the parcels it wins or held. A write is done when every parcel the layout
  asks for has landed; a store down passes its parcel to the next in line, moved back by a repair
  later. **A repair must run on its own while the control plane is lost**, since until it does, data
  is held below its placement. Decided by the author on 2026-10-20: **placing a hash answers at
  once**, stricter or looser, as the storage asks from the strictest of what names it, its parcels
  moved in the background and readable throughout, a describe showing the placement it has and the
  one it is moving to; **a key's version retired is a task**, `rekey`, answering its id at once and
  told by `task(id)`, RFC 49qyg; **a list is for a sweep alone**, by hash a page at a
  time, each with when it was put, against the sweep's grace.
- **A machine tablet's copies carry SQLite's WAL frames as they are**, the primary's to the rest,
  decided by the author on 2026-10-20, never its statements; an append carrying no frame renews the
  lease. **Their rules are sampled at their own interface**, the frames a sample asks for made by a
  real SQLite from the statements it names, beside the database's samples losing copies; and **the
  protocol is proven by a model checker**, every interleaving of a primary lost, a copy lost and a
  partition run against a specification, before a platform holds its users' data [C1].
- An executor runs code in one of two sandboxes.

**Every dependency points down**: a product reaches the issuer, the tablet, the blob and the
executor; the tablet reaches the blob to persist; the blob
reaches the scope's backing and the extent, below it, RFC b8f35.

**The constants v0 picks**, worked out with the author on 2026-10-19, each in code and changed by
a release:

| Constant                                         | Value                                                                    |
| ------------------------------------------------ | ------------------------------------------------------------------------ |
| a capability's life                              | an hour, or 15 minutes where its organization's `security` is `strict`   |
| an account credential's life                     | 12 hours, or an hour where its account's `security` is `strict`          |
| an organization's key that signs capabilities    | certified for seven days and renewed every day, RFC v7v3w                |
| a sweep's grace, before bytes nothing names go   | 24 hours, past the slowest upload between bytes and their name           |
| a machine tablet's WAL, archived to the storage  | at 16 MiB, a parcel's size, RFC b8f35                                    |
| a primary's lease, held among its copies         | 10 seconds, renewed every 3                                              |
| the longest a write waits after a writer is lost | 15 seconds, the lease and a new writer's catching up; then `unavailable` |
| an object's longest extension                    | 16 characters, RFC 13ixj, only ever raised                               |
