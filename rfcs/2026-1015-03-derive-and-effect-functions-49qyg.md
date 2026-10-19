---
name: 'Derive and Effect Functions'
title: 'An app runs as functions that keep no state of their own, of two kinds: derive, whose output its input alone decides, cached and run again freely, and effect, which acts on what it is bound to and is never retried'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

The platform is to give an app three stable things -- functions to run in, a database and a
storage -- and keep everything beneath them its own. Worked out with the author on 2026-10-15, top
down from what an app needs, before any implementation and apart from every earlier design of how
the platform runs an app; how it lands is left for after this round. The storage is RFC 13ixj and
the database RFC zn3u5. The question here is what a function is to an app.

This is layer 0, the platform's face, as RFC vuanj numbers the layers.

The shape the discussion has reached so far, to be decided once it is diffed against what exists:

**A function may hold state while it runs, and none after.** Its memory during a call is its own;
whether any of it is still there at the next call is the platform's to decide, so an app may cache
in it and never counts on it. What lasts goes to a database or a storage it is bound to. A function
runs anywhere and at any time, and wherever it runs, what it is bound to is reachable from there.

**A function declares what its code needs, never where it runs**, each function on its own rather
than its app as a whole. **A need, what a scope allows and what the platform can give are written in
one vocabulary of capabilities**, each with a name, a type -- yes or no, an amount with its unit, one
of a set, or some of a set -- the rule that compares two, and a default. Deploying checks that what is declared
fits what the scope allows, its allowance, RFC vuanj, refused in a state that names the capability
when it does not; running checks that it fits what the platform can give, `unavailable` when it
does not. A capability added later is one more entry, and nothing that checks changes. **The first
entries are the two settled**: the kind, and **`network`, some of `http`, `tcp`, `udp` and `icmp`**,
`http` alone by default -- grouped under one name as `env` holds `config` and `secret`. A third is
**`instance`**, yes or no, no by default: a place that offers it delivers every call for one key to
one running instance, as a long-running process on a machine does and a runtime that pools its
instances does not. A tablet's writer is placed only where it is offered, RFC vuanj, and a `keyed`
daemon has its shape. They are
apart because each is apart where it matters: what a sandbox can give, and how much risk a scope is
allowed. `http` goes out only through the platform's own request interface, which it can see and
limit, though it runs over TCP, and which checks for each request that its call declared it; `tcp`
is any socket, and it, `udp` and `icmp` leave from the host that offers them, never through that
interface; a function that needs to ask DNS itself declares `udp` and is not made to ask for `icmp`
with it.

**A function is one of two kinds, and the kind is part of what it declares.**

**`derive`: the output is decided by the input alone.**

- **It is given no capability that could make it otherwise**: no binding, no network, and no clock
  or randomness but what its input decides. Purity is enforced by what it lacks, never taken from
  what it claims, since a cache that trusted a claim would hand one caller another's wrong answer.
- **Its outcome is a result or a panic, and both are decided by the input.** It is bounded by a
  budget counted in a unit that is the same on every machine, never by wall time, so the same
  input exhausts it at the same place everywhere; exhausting it, or its memory, is a panic.
- **It is run again wherever it was interrupted**, since running it twice changes nothing; a machine
  lost under it is never seen by its caller.
- **It is cached**: the key is the hash of the function's code and the hash of its input, so a new
  version is a new key and nothing is invalidated by hand. A panic is cached as a result is. Its
  output is content, kept as the storage keeps content.

**`effect`: it acts on what it is bound to, and on the world.**

- It reads and writes its bound databases and buckets, and reaches the network.
- **It is never retried by the platform** on its own judgment: whether to call again is its caller's.
- **A write waits for a lock rather than failing on one**, so the time spent waiting is mixed with
  the network's and barely seen. The wait is bounded and so is how long a lock is held; past either
  it fails as `unavailable`.
- **Waiting promises nothing about what is found.** A conditional write whose condition no longer
  holds when its turn comes fails as `rejected`, at once, and never waits.

**A call to an `effect` ends one of four ways**, told apart by what the caller most needs to know:
whether it took effect, and whether trying again could help.

| Outcome       | Took effect    | Trying again                       |
| ------------- | -------------- | ---------------------------------- |
| success       | yes            | --                                 |
| `rejected`    | certainly not  | useless until something changes    |
| `unavailable` | certainly not  | may succeed later                  |
| `unknown`     | cannot be told | only once the outcome is looked up |

- **A call returns an id, and an id is never an input.** No function takes one as a parameter; the
  platform makes it, time-ordered, and hands it back.
- **`status(id)` is the one function that takes an id**, given by the platform and rarely called:
  it answers what became of the call. Calling it returns no id of its own, so asking after a call
  never needs asking after in turn.
- **Two requests for the same thing are the app's to tell apart**, never the platform's: a key of
  the app's own, sent as an ordinary parameter and held unique in its database, refuses the second
  as `rejected`.
- **Every id expires**, briefly: what serves it applies it before then or never. So "not seen",
  once the id has expired, is certain, and an outcome is never left open for good.
- **An outcome not known at once is looked up, not handed to the app**: the platform holds the call
  and asks after its id until it has an answer or a deadline passes. Only then is it `unknown`, which
  carries the id, how long it was looked up for and the last step known, and `status(id)` finds the
  outcome once it can be found.
- **An `effect` that wrote twice and stopped between is `unknown` too**: each batch is atomic, two
  are not. What must change together goes in one batch, RFC zn3u5.

**A long-running process is not a function: it is a `daemon`**, now a `container`, or several
that stand in for one another, RFC vr5lw. A browser held open, a chat client
logged in: it starts, runs, and is reached through the `effect` functions it exports. Its output is
the world's -- a page differs by time, place and address -- so what it exports is `effect`, never
`derive`, however many of it run. What it writes as it runs, a browser's cache or a chat client's
history, may be lost at any moment; what matters leaves through its exports to a database or a
storage. A daemon is one of two kinds:

- **`pool`**: copies that stand in for one another, as many as the load needs, any one answering.
- **`keyed`**: exactly one per key, a chat client per account, never two at once.

**Configuration and secrets are both env**, an entry's kind `config` or `secret`. **A change to env
reaches the next deployment and nothing running**: an app or a daemon keeps the env it started
with until it is deployed again, as on Cloudflare and Vercel.

**A function is started three ways.**

- **`request`**: over HTTP, on demand.
- **`schedule`**: at set times. A time missed for any reason, the platform down among them, is not
  run late one by one: once it can run again, only the last missed is run. A time is delivered at
  least once and never promised exactly once, so the platform drops a repeat by the schedule and
  the time it was due before it runs, a guard kept in the function product's own tablet.
- **`queue`**: a message an app submits to a queue, by `submit`, handled later. **Retrying is chosen here and
  nowhere else**, which is why an `effect` called directly is never retried: an app that wants a
  failure tried again puts the work in a queue. Every queue declares what a failure does -- the
  message dropped, or retried, and then it declares how: how many times and how far apart. A
  message that runs out of tries loses its parameters, and its id and what is needed to know it died
  without finishing go to a dead-letter list, where it can be found.

**One app reaches another only through what the other exports, and both declare it.** B declares
each function it exports: its name, its kind, its parameters' types, and how far it is shown --
within its organization by default, or public, RFC vr5lw. A declares which of B's
functions it calls. Deploying A is refused when what it calls does not match what B exports, by the
number of parameters and their types -- never their values, which are A's business. Deploying B is
refused when it would take away or change a function something still calls, and deleting B is
refused while anything calls it, naming the caller: the callers go first. **The calls form a graph
with no cycle**, so a first deployment and a deletion always have an order. **The bindings are in
the same graph**: a bucket or a database is refused deletion while an app is bound to it, naming
the app, so an owner deletes from the leaves inward. How a scope itself is deleted is RFC vuanj's.

**No app calls an app of another organization**, the owner of a scope, RFC v7v3w. A call across
scopes is refused when deployed, in a state of its own whose reason is said as it is: calls across
organizations could close a cycle that no single scope can see, and no organization could order a
deletion across one. An organization that wants another's app reaches it as a third party does: the
other exports a public API, and the caller reaches it over the network as an `effect`, its
`unavailable` the caller's to handle -- as any dependency on someone else should be.

**A parameter's type is described in WIT**, the WebAssembly component model's interface language, or
a subset of it taken when this lands: it was made for typed exports and imports between parts
written in different languages, which is what A and B declare to each other.

**What a build declares and what its owner configures are apart**, worked out with the author on
2026-10-19, told by what changes when one build is deployed in another organization. The build's
manifest declares its shape, and goes with its version: its functions, each one's kind and needs,
its exports and the calls it makes, the binding slots it needs -- a name and a type, `uploads` an
object bucket -- the env keys it reads, each `config` or `secret`, and its schedules and queues. The
owner configures what fills it, and goes with the organization. So one build deploys anywhere its
slots are filled, and going back a version takes its whole shape back and leaves what fills it.

**An app's record holds**: its `version`, the hash of the build deployed, whose manifest is found by
it; its `bindings`; and its `env`, each key's value, a secret's sealed. **Nothing in it makes the app
public**: an app is reached from outside only once it is mounted under its organization's gateway or
a name of the organization's own is bound to it, each an act of its own, RFC vr5lw, and it is
neither as it is made.

- **A schedule and a queue are a build's, never records of their own**, worked out with the author
  on 2026-10-19: their times and a queue's failure are declared in the manifest and go with its
  version; a queue's messages are data, and the guard against a schedule's repeat is the function
  product's own tablet's, above.
- **Bindings are nested by the type of what they hold**, `app`, `database` or `bucket`, the types
  of an organization's tree, RFC v7v3w, and within each a slot's name to an id: an app called is a
  slot as a database used is. A deployment is refused where the slot's declared type, the type it
  is filled under and the type of the resource the id names disagree, saying which, so an id filled
  in the wrong place is caught where it is written and never resolved to whatever it names.

Open, for the discussion that follows:

- How a `keyed` daemon's own credentials reach it, an account's login: env is the same for every
  copy of a deployment, so these may be what it is started with rather than env. [C11]
- How a daemon is started, addressed and ended, given that any may vanish at any moment; a `keyed`
  one, exactly one per key, has the shape of a tablet's writer, placed at run time with at least one
  promised and the rest fenced, RFC vuanj. [C11]
- Every capability past the kind and the network -- where a function's requests leave from, how long
  it may run, its resources -- each of which is at once a need, an allowance and what the platform
  can give, and is entered in the vocabulary when it is taken up. [C11]
- Which imports a `derive` is denied in WebAssembly -- files, the network, the clock, entropy and
  the rest -- examined one by one when it is built. [C11]
- Whether an exported function carries a version, so one can change while its callers move. [C11]
- Whether a change in storage starts a function, perhaps by putting a message in a queue. [C11]
- Every bound: the `derive` budget, the longest wait for a lock and the longest hold, how long an id
  lives, how long an outcome is looked up before it is `unknown`, and how much a dead-letter list
  holds and for how long. [D4]
