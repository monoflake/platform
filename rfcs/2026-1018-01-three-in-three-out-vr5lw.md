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
- **`object` is a contract of the platform's own, written as a subset of S3**, worked out with the
  author on 2026-10-18: putting an object whole, getting it whole or by a range, asking whether one
  is there, deleting it and listing by a prefix, each read seeing every write before it -- what the
  blob asks, RFC vuanj, and no more. Every object is at most 16 MiB. It needs no condition on a
  write, since a container is named by its content and a journal's object by a seed drawn at
  random, no rename and no upload in parts. **What takes it and what gives it are one**: a store
  is reached by it, and a platform gives an `opaque` dataset by it, RFC 13ixj, so one platform's
  storage is the next one's `object`, RFC 94y0d. A `content` dataset may be given by the same
  subset without the 16 MiB bound, for a client that speaks S3.
- **Each is made of what is beneath it**: an `object` store of compute and a volume; a database of
  compute and a volume, below; a dataset of compute, `object` stores and a database, its records'
  home, RFC b8f35.
- **What is extended is `object` and volumes; what is given is `object` and datasets.** A dataset is
  the platform's own and never taken from beneath: a platform above takes the one beneath as
  `object`, through its `opaque` datasets, so nothing is cut or sealed twice, RFC 94y0d.
- **A volume has no interface but the files it holds**: a file system mounted into one container
  alone, kept past a restart, and on a disk once flushed. It is never reached over a network, since
  being mounted by one alone is what keeps a database on it to one writer; storage reached over a
  network is `object`.
- **A database is made of compute and a volume**, a `container`, whose one volume is mounted by it
  alone and so keeps the database to one writer; a vendor's instance, one per key, does the same
  with a store of its own. Some resources give a database already, a small one. **Whatever gives a
  database gives it in the platform's own contract**, SQLite's dialect and atomic batches,
  `scope.md`, never a vendor's.
- **A database is reached by an HTTPS interface of the platform's own, and the least**, worked out
  with the author on 2026-10-18: one statement, or one batch, each SQL with its parameters, answered
  with each statement's rows. No vendor here speaks a common protocol for it -- D1 is reached from a
  Worker, a machine's SQLite is a file -- so every driver adapts whatever is chosen, and the least
  leaves nothing to adapt that the contract forbids. How a value of SQLite's is written in it is
  open [B7].
- **Each host's driver declares its databases' limits** -- a statement's size, its parameters, how
  long a query may run -- as it declares its levels: a vendor's in the code, which knows the vendor,
  as D1's from `lessons.md`; a machine's from a default the platform gives, which its holder may
  change. The platform holds each database to what is declared of it.

**Whatever runs is deployed as its configuration is applied, never loaded as a call comes**,
worked out with the author on 2026-10-18. Since opening anything is a change of configuration, RFC
v7v3w, each has a moment it is applied, and a task, which no one waits on in a dashboard, deploys
it then: an app's version, a database's writer, an `object` store made of a volume, a part of the
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
- **What a control asks depends on the driver's kind**, and only what the platform uses -- a
  domain's records, a shell -- never the host's whole. Without either a binding still works: what a
  Cloudflare driver opens is reached at the address the vendor gives it free, as a Worker's.

- **A management token or a shell key is the control's configuration**, kept by that control alone, sealed as its
  other secrets are [B4], and never in a bundle, since nothing serving needs it.
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
    platform's; none at all is allowed too, a holder reaching the machine by its console instead.
    Recognizing a key by its form is for showing, never for trusting.

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

**Who may call is a capability's to say; who can reach is the network's, and kept apart.** Worked
out with the author on 2026-10-18.

- **Each export declares how far it is shown**: within its organization, the default, called by its
  organization's apps with a capability at its deployment's address; or public, which it is
  exactly when a name is bound to it. Nothing is public that no name is bound to. Within an organization an address
  may still stand on the public network, and every call to it without a capability of its
  organization's is refused; a network laid over the public one, keeping such an address off it,
  is a guard beside that, and open. [C25]
- **A machine's driver keeps its firewall**, in software, so no hardware firewall is needed: what
  comes in is let in only at a public export's port and the driver's own, and what goes out only as
  each deployment's `network` allows, RFC 49qyg.
- **An app is reached from outside where it can be reached and can be found**, worked out with the
  author on 2026-10-18: reached, by an address of its own or a relay; found, by a name bound to it.
  **An entry is that name and nothing more**: on a machine, a listener its driver deploys beside
  the deployments, as it deploys an adapter, so data still goes past the driver, ends TLS with the
  machine's certificate and hands a request to the deployment its name is bound to; a Worker is its
  own entry. No route table stands beside the names. An entry reads the name alone and carries the rest
  unread, answers unavailable while what the name is bound to is down, and never authenticates an
  app's users.
- **A gateway is an app, never a part**: an app bound to a name, calling others of its
  organization by capability, inline or across machines, and limiting rate or authenticating its
  users in its own code if at all. What stands behind it is shown within its organization alone and
  needs no name. The platform keeps no gateway and reserves no name for one.
- **A name bound to a machine's app is a record DNS only**, pointing at the address its driver
  reports, which it reports again as it changes, so a machine's address being fixed, changing or
  new at each restart is all one. A name of the user's own points at a platform name by a CNAME,
  behind a proxy of their own or not as they choose; the platform binds no domain of a user's
  itself. The two may stand together. A machine without an address is reached through a relay of
  Cloudflare's, above.
- **A Worker is public at the address its vendor gives it**, or at a domain its account holds,
  bound in that account.
- **A platform's name may be served from a user's own Cloudflare account**, its traffic counted
  there: where that account holds a domain of its own and the platform holds a management token
  for it, the domain's zone takes the platform's name as a custom hostname, served by a Worker on
  the zone, and the platform, holding its own domain's records, proves the name and points it there,
  DNS only. Its certificate is the vendor's, one for that name, asked of Google's CA so it
  takes nothing of Let's Encrypt's count for the platform's domain; that a name four levels deep is
  given one across accounts is to be tried. [C26] Where it holds no domain, the vendor's address or the user's own domain serves instead.
  `lessons.md`
- **An organization is given two names, `{organization}.{domain}` and `*.{organization}.{domain}`**,
  of a domain apart from the platform's own, as a vendor keeps its users' pages off its own domain,
  so nothing an organization's app sets reaches the platform's console or controls. It binds any
  name the two cover -- the first, or one label beneath it -- to any of its apps, as it likes; an
  app's name is offered as the label when the app is made, and binds nothing. Which organization
  holds a label of the domain is the platform's control's record, kept beside the anchor in the
  platform's footing; which app a name of the organization's is bound to is its own control's, and
  a name is bound to one app at a time. Organizations are kept
  apart from one another by that domain's place in the Public Suffix List, asked for once the
  platform serves thousands, which the list asks, `lessons.md`. [D9]
- **A certificate service gives a machine its names' certificate**, worked out with the author on
  2026-10-18: an app like any other, in an organization of the internal platform's own, which asks a
  public CA by ACME and its DNS challenge -- Google's first, which counts no domain's certificates;
  Let's Encrypt beside it -- and renews and, where its CA allows, revokes.
  - **A key never leaves its machine**: the driver makes it and hands the service a request for a
    certificate, and the service gives back the certificate alone, renewing on the same request
    until the driver makes a new key.
  - **It holds no token able to move a name**: each platform name's `_acme-challenge` is delegated
    by a CNAME to a zone kept for validation alone, and the service holds a token for that zone
    only; the records that point a name stay the platform's control's.
  - **A machine is given one certificate for `{organization}.{domain}` and
    `*.{organization}.{domain}`**, its own key behind it, so a name bound to an app there is served
    at once. Its holder could answer for another of the
    organization's names only where that name's traffic reached it, and the platform points the
    names. Let's Encrypt issues one set of names five times a week, so through it an organization
    adds five machines a week at most, `lessons.md`.
  - A driver asks for a name's certificate with a capability naming it.

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
