---
name: 'Five Parts Under the Products'
title: 'The storage, the database and functions are built side by side from five parts -- scope, issuer, tablet, blob and executor -- and never from one another, so nothing beneath an app depends on itself'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFCs 13ixj, zn3u5 and 49qyg settled what an app sees: a storage, databases and functions.
Working one layer further down with the author on 2026-10-15, each seemed to need the others -- the
storage's metadata a database, a database a file in the storage, a function's cache both -- and
a platform that depends on itself is the problem this design began from. The question is what the
products are made of, and in what order, one layer only: where each part runs is layer -2's.
Names are chosen for what they mean, apart from the names the platform uses now; a clash is settled
when this lands.

The shape the discussion has reached so far, to be decided once it is diffed against what exists:

**Layers are numbered from the platform's face, layer 0**, upward to what users build and downward
to what the platform is made of:

| Layer     | What it is                                                                 |
| --------- | -------------------------------------------------------------------------- |
| +1 and up | Users' apps, the console's dashboard among them, an app like any other     |
| 0         | The products an app sees: the storage, databases and functions             |
| -1        | The parts the products are made of, this RFC                               |
| -2        | What the parts stand on: backings, the extent and hosts, RFC b8f35         |
| -3        | The anchor, the one global state, on a vendor's primitive, RFC b8f35       |
| -4        | The root, which depends on nothing and everything needs, RFC b8f35         |
| ground    | Each owner's footing, one database, and the vendors' primitives, RFC b8f35 |

**The platform runs on itself wherever an ordinary owner could.** What the platform runs is of
three kinds:

- **What an ordinary scope's permissions are enough for**, the console among them, is deployed in
  an organization of the platform's that holds no privilege, down the path every owner takes. It may
  be given a larger allowance, which is a value, not a privilege.
- **What needs a privilege no owner holds**, reaching across scopes, never shares the owners' path,
  so nothing on that path has to tell a privileged request from another, or can let one leak. It
  runs apart, beneath that path. The platform's control is one, and the only one known: an HTTPS API on the platform's footing, in
  no organization, RFC v7v3w.
- **The parts at layer -1 and below**, which keep the platform up and place what owners run. They
  are no app, and are never placed among apps.

This holds only while the graph is clean: nothing the platform needs to start, restart or come back
stands on what it runs as an owner.

**The cycle came from drawing one layer where there are two.** Beneath the products are parts, each
smaller than any product, and **the three products stand side by side on the parts and never on
one another**. A product that looks like another -- a database's name pointing at an id, a
dataset's path pointing at a hash -- shares a pattern with it, never a dependency.

| Part       | What it is                                                         |
| ---------- | ------------------------------------------------------------------ |
| `scope`    | Whose data this is: an opaque id, what it holds, what it may use   |
| `issuer`   | Signs the capabilities every other part checks                     |
| `tablet`   | One small SQLite with one writer: SQL, and an atomic batch         |
| `blob`     | Bytes by the hash of their content: put, get, delete               |
| `executor` | Runs a function's code on an input, in the sandbox its kind allows |

**A part knows a scope and never a user.** A scope is an organization's, RFC v7v3w; accounts and
logins are above; which user owns
which scope is not a part's to know. Every tablet and every blob belongs to exactly one scope and
never crosses it, so a product with a fault cannot reach another scope, a scope's usage is counted
where it is kept, and a scope is deleted whole. A scope's salt and key, and the stores its bytes go
to, are its physical half, the backing at layer -2 -- RFC b8f35 -- which the blob reads downward;
the salt and key are derived from a master secret and the scope's id, so neither is stored; and
since its key can always be derived again, a scope is never deleted by losing its key, only by
deleting its bytes.

**A scope is deleted one of two ways.** Its owner deletes what it holds from the leaves inward, as
the graph of dependencies orders it -- the apps first, then the datasets and databases they were
bound to, then the scope -- and nothing is deleted while something depends on it, RFC 49qyg; only
then may the owner close their account, which is above. The operator, revoking an owner, stops at
once everything it holds and deletes nothing, RFC v7v3w: a privilege of the platform's, never an
owner's. A scope so suspended is deleted after seven days unless it is restored, RFC b8f35.

**No part trusts its caller: it checks a capability.** A capability names a scope, a resource, an
operation and when it expires, and is signed by the issuer alone, through a chain parts verify
with the root's public key and never call at run time -- RFC b8f35. A call is given only the
capabilities its app's bindings allow, for that call alone, and passes them down: a product checks
the resource -- a dataset, whether writes are allowed -- and a part checks the scope. The issuer is
its own part, reading each scope's grants from its organization's bundle, in the footing, RFC
v7v3w. Authenticating the
people who use an app is another matter, above.

**The operations are five, each a right of its own**: read; create, which is refused where what it
would write already exists; replace, which overwrites what exists and so can lose it as a deletion
can; delete; and alter, a database's schema. Create apart from replace makes a holder that can only
add -- a backup, an audit log -- which, taken over, cannot erase. Alter is given only while a
migration runs, RFC zn3u5.

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
at deployment, and read as the data plane works, on each call.

**Inside a scope each product has its own blob space**, since what counts the references to a hash
is the product's own tablet; two products sharing one would delete what the other still holds.

**The storage** reads its datasets and their policies from the bundle, and keeps one tablet per
scope for the rest of its metadata -- each path's hash, each
hash's size, references, strictest policy and whether it is public, each directory's size -- and
its content in its blob space. A write puts the bytes first and then changes the tablet in one
batch, so a fault leaves at most bytes nothing names, which a sweep removes, and never a name
without its bytes. A hash nothing names is marked and removed later, never in the write.

**A tablet is a log and a snapshot.** Its one writer runs each batch on its SQLite and turns it
into an entry of a log, numbered in order, and that number is the cursor a write returns. The log
is kept in the scope's footing, RFC b8f35: **a write is done once the footing has confirmed it**,
and the log is archived to the blob in batches, with a snapshot of the whole now and then, and
removed from the footing once archived. From there the rest
follows:

- **A read copy** applies the log as it comes and knows the number it has reached; a read with a
  cursor goes to a copy that has reached it, the next if not, and the writer if none has.
- **Returning to an earlier time** is the snapshot before it and the log replayed up to it.
- **A batch's id and expiry** are written in the tablet's own system table in the same transaction
  as the batch, so whether one was applied is answered exactly, and an expired one is refused.
- **A writer handed over** is fenced by the footing: the new one catches up and is made writer at
  the next generation, and the old can write nothing after; writes wait the few seconds it takes,
  and reads go on from the copies.
- **Where a writer runs is placed at run time**, since a database may be created at any time, never
  only at a deployment. What places it promises at least one writer and never exactly one: two may
  run for a moment, and the generation the footing keeps refuses all but one.

A user's tablet has one copy unless its owner asks for more, as data in the storage does.

**A `transactional` database is a tablet**, and the product adds what an app sees: a directory of
names, ids, the one app each belongs to and whether read copies are on, which is configuration and
read from the bundle. A capability
covers the databases of one app, so a database created for it is reachable once the organization
holds the bundle that records it, RFC v7v3w.

**A function** keeps its code in its blob space, its code's hash its identity; its declarations
are configuration, read from the bundle, and a deployment checks the types and the call graph,
the calls never crossing a scope since they never cross an owner; its calls, their ids,
outcomes and expiry, in a tablet `status(id)` reads; its `derive` cache as a tablet indexing a
code's hash and an input's hash to an output kept in blobs, since a blob's hash is its content's and
cannot be chosen; its queues' messages and its schedules' repeats in tablets, the queues and
schedules themselves being configuration, in the bundle. **The executor stores nothing**: it is given
the code's hash, the input and a sandbox -- for `derive` nothing at all, no capability, network, true
time or randomness; for `effect` the call's capabilities and the network -- and gives back the output
or a panic.

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
  checks a declaration against. Code is fetched by its hash from the blob, and kept where it ran,
  since what a hash names never changes.

**What the products ask of the parts:**

- A tablet runs SQL and atomic batches; returns a cursor with every write; keeps read copies and
  answers a read with a cursor no older than it; returns to an earlier time; archives itself to its
  blob space; and records each batch's id with its expiry, refusing one that has expired, so an
  outcome can always be found. Every capability past the first is used only where a product needs
  it.
- A blob puts bytes with a placement and answers their hash, gets them whole or by range, raises a
  hash to a stricter placement, deletes, and lists, for a sweep alone. Below that face it encrypts
  with the scope's key, lays the bytes out as the placement asks, and places each container among
  the scope's stores: each store a container may go to is scored by a hash of the container and the
  store, and it goes to the highest, RFC b8f35 -- so anyone with the same stores finds the same
  places, more copies take the next in line and leave the first where they are, and a store added or
  removed moves only the containers it wins or held. A write is done when every container the layout
  asks for has landed; a store down passes its container to the next in line, moved back by a repair
  later. **A repair must run on its own while the control plane is lost**, since until it does, data
  is held below its placement.
- An executor runs code in one of two sandboxes.

**Every dependency points down**: a product reaches the issuer, the tablet, the blob and the
executor; the executor reaches the blob for code; the tablet reaches the blob to persist; the blob
reaches the scope's backing and the extent, below it, RFC b8f35.

Open, for the discussion that follows:

- How a private link's reader proves they may read it: the authentication of people, not parts.
  [C10]
- Every lifetime and bound: a capability's, a blob's grace before a sweep, an id's. [B14]
