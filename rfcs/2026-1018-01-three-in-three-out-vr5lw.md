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
  such as Docker. The storage's 16 MiB unit of sealed data, RFC b8f35, shares the word and nothing
  else, and is to be renamed. [A10]

**Storage is of two uses, and only one is offered above as it is.**

| Use      | What it is                                                                                       |
| -------- | ------------------------------------------------------------------------------------------------ |
| `object` | the storage's own: datasets of files by name, RFC 13ixj, narrower than S3, and optimized beneath |
| `volume` | a disk: bytes changed in place and flushed, mounted by one `container` at a time                 |

- **A volume can give `object`; `object` never gives a volume.** Datasets can be kept on a disk,
  but a disk cannot be made of files written whole, however fast: a database changes a few bytes
  of a file and must have them flushed at once, one writer at a time.
- **A database is made of compute and a volume**, a `container`, whose one volume is mounted by it
  alone and so keeps the database to one writer; a vendor's instance, one per key, does the same
  with a store of its own. Some resources give a database already, a small one. **Whatever gives a
  database gives it in the platform's own contract**, SQLite's dialect and atomic batches,
  `scope.md`, never a vendor's.

**What each resource gives:**

| Resource                    | Compute                                    | Storage               | Database                                      |
| --------------------------- | ------------------------------------------ | --------------------- | --------------------------------------------- |
| a machine, a VPS or at home | function, `instance`, `container`          | `object` and `volume` | one its driver makes, a container on a volume |
| a Worker                    | function                                   | --                    | --                                            |
| a Durable Object            | `instance`, once metering holds, RFC 94y0d | its own small SQLite  | a small one                                   |
| D1                          | --                                         | --                    | a small one                                   |
| R2                          | --                                         | `object`              | --                                            |

**A platform's footing is one of each, and for its control alone.** Beneath every platform is one
compute, one storage and one database, each meeting one kind of its class at least -- a Worker's
function, R2's `object` and D1 give the internal platform's -- trusted as ideal, `scope.md`. Its
compute must give a function, and `effect` among it, since a control writes and answers an API; it
needs no `instance`, keeping its state in its database alone. Only the platform's control uses
them, RFC v7v3w.

**Every organization is kept as the platform is: a control on a footing, and its apps on what it
extends**, RFC v7v3w. Its control stands on one compute, one storage and one database the platform
gives it, and keeps its records there; its apps stand on the compute and storage extended into it,
of any kinds, and databases given in the platform's own contract or made of compute and a volume.
Above, a platform
gives as many of the three as it has organizations to give them through.

**A platform takes nothing from beneath but what a driver gives**, worked out with the author on
2026-10-18. A host -- a machine, or a vendor's account, Cloudflare's as one -- runs one driver, on
itself: on a machine as a process, on an account as what that account runs. One driver gives every
kind its host can, of compute, storage and databases, in the platform's terms; it serves every
binding of it, of any organization on any platform, and keeps them apart, RFC v7v3w; and its own
management it shows to no binding. The internal platform gives an organization's three products to
the external one through the same interface, so one platform's output is the next one's input, and
one code is both.

- **A driver manages, and data goes past it.** It opens, lists and ends what it gives, and reports
  usage; for each thing opened it hands back an address and a credential for that thing alone,
  which speaks the platform's contract -- the vendor's own interface where it already does, an
  adapter the driver deploys beside it where it does not, as a Worker in front of D1, RFC b8f35.
- **A driver holds its host's credentials**, put there by whoever holds the host; a control holds
  none of them for what the driver gives, and takes one only to configure the host, below. Using a driver is trusting that holder, who can read what runs and what a
  database keeps, and remove the driver, which nothing prevents; only what storage keeps is sealed
  against them, RFC b8f35.

**A driver is managed by a list, and keeps the least it must**, worked out with the author on
2026-10-18. What follows is its management alone; each primitive's contract is open. [B7]

- **A binding comes of a credential the host's holder makes** on the driver's own management, which
  no binding sees -- a command on a machine, a secret on an account -- and gives an organization's
  admin, who enters it in that organization's control.
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
  and when each difference was first found. Everything else it reads from its host.
- **What a driver has to tell, it pushes**, as events, each with an id: a difference found, a thing
  removed, a thing that cannot be made. It pushes to each binding's control what is that binding's
  alone; one it could not deliver it pushes again later, and hands back as well with the state a
  control asks it for, so an event is never lost, and its id lets it be taken once. No one polls.
- **Liveness is a heartbeat, and the driver's alone**: small, and its own to pace, or none where the
  host is always reached, as a vendor's account. Whoever needs to know a host is up asks its
  driver's heartbeat, and keeps none of its own.

**Configuring a host is a privilege apart, never the driver's.** Worked out with the author on
2026-10-18: a driver gives compute, storage and databases and nothing else, and some of what a
host offers is none of them -- a domain's records on Cloudflare; a shell on a machine, its packages,
its reboot. A control, the platform's or an organization's alike, reaches these with a credential
of its own that the host's holder gives it, beside the binding: an API token of the account, or a
key pair the control makes whose public half the holder installs. What it asks depends on the
driver's kind, and it asks only for what the platform uses -- a domain's records, a shell -- never
the host's whole. Without one a binding still works: what a Cloudflare driver opens is reached at
the address the vendor gives it free, as a Worker's.

- **The credential is the control's configuration**, kept by that control alone, sealed as its
  other secrets are [B4], and never in a bundle, since nothing serving needs it.
- **It is the holder's to give, as often as they like**; two controls given it for one host may
  undo each other's changes, which is the holder's choice, never the platform's to settle.
- **A control configuring a host never takes the holder's own way in away**: it may disable a
  machine's password logins once its own key works, and keeps the holder's.

**A call between resources takes one of three ways**, chosen by the platform, never by the caller:

| Way    | When                                                                                                              |
| ------ | ----------------------------------------------------------------------------------------------------------------- |
| inline | both ends are given by one driver, which offers a way within its host: an account's binding, a machine's loopback |
| direct | the end called has an address of its own on the public network                                                    |
| relay  | the end called has none, as a machine at home: it is reached through a relay its user chooses                     |

- **Inline is the platform's to take, since it changes the way and nothing else**: the contract and
  every capability checked are those of the public network, RFC 94y0d, so where its condition holds
  it is always taken.
- **A relay is a driver's**, never a container of its own: Cloudflare's, or a machine's with an
  address of its own. It is asked only for what comes in -- a machine without an address reaches out
  directly -- and carries what passes encrypted end to end, so its holder sees who speaks and how
  much, never what.
- **A host without an address is told so as it is bound**, by whoever binds it, and its driver
  checks it by asking a relay to dial the address back; where they disagree it warns, and changes
  nothing of itself.
- **Which relays a host may use is configuration**, chosen as it is bound: one or more, or all, the
  relays among what its organization binds. **It holds a lasting connection to every one of them**,
  costing little while idle, so a caller reaches it through whichever is nearest the caller, and
  the first handshake is always right: no one keeps which relay is best, and nothing the data plane
  needs waits on a control. A host answers back by the relay nearest its caller. A relay of
  Cloudflare's is one name its network finds the host behind, `lessons.md`.
- **A relay is withdrawn by its organization's control**, from what it observes -- a host's traffic
  spent, say -- as any configuration changes: the new list reaches the host in its bundle, which
  connects to what is new before it drops what is gone, and keeps what stays.
- A vendor's thing without an address of its own, as D1, takes the address of the adapter its
  driver deploys, and needs no relay.

**So one platform is built on another by an organization.** The external platform's footing is the
three that one organization of the internal platform gives; its control stands on them alone. An
organization opened on the external platform has its footing, and the compute and storage it buys,
from a shadow organization the external platform opens on the internal one through the internal
platform's control; what else it extends comes from the user's own clouds. The internal platform's own extensions come from
third-party vendors and the author's machines.

Open, for the discussion that follows:

- The database's sizes, a small one and a large one, and what each is made of. [C23]
- The new name for the storage's 16 MiB unit. [A10]
- The driver's interface, and each primitive's contract in it: how an `object` store, a database and
  a compute are reached, deployed to and called. [B7]
