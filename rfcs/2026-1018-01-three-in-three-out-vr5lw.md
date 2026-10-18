---
name: 'Three In, Three Out'
title: 'A platform takes compute, storage and a database from beneath and gives compute, storage and databases above, one of each beneath for its console alone and as many as it likes above, every other organization standing on the compute and storage it extends'
status: draft
supersedes: []
blocked-by: []
commits: []
references: []
---

## Question

RFCs v7v3w and 94y0d stand two platforms one on the other, and reserve an organization, `console`,
on each. Worked out with the author on 2026-10-18: what a platform takes from beneath, what it gives
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
- **A database is made of compute and storage**: an `instance` or a `container` for its one writer,
  and a volume or a store of its own. One volume is mounted by one container, and a vendor's
  instance is one per key, so either is the referee that keeps a database to one writer. Some
  resources give a database already, a small one.

**What each resource gives:**

| Resource                    | Compute                                    | Storage               | Database                                 |
| --------------------------- | ------------------------------------------ | --------------------- | ---------------------------------------- |
| a machine, a VPS or at home | function, `instance`, `container`          | `object` and `volume` | none of its own; a container on a volume |
| a Worker                    | function                                   | --                    | --                                       |
| a Durable Object            | `instance`, once metering holds, RFC 94y0d | its own small SQLite  | a small one                              |
| D1                          | --                                         | --                    | a small one                              |
| R2                          | --                                         | `object`              | --                                       |

**A platform's footing is one of each, and for its console alone.** Beneath every platform is one
compute, one storage and one database, each meeting one kind of its class at least -- a Worker's
function, R2's `object` and D1 give the internal platform's -- trusted as ideal, `scope.md`. Only
the `console` organization uses them, and its app, `control`, the platform's control plane, uses
nothing else.

**Every other organization stands on what it extends.** Before an organization other than the
console runs anything, compute and storage are extended into it, of any kinds; a database is
never extended, and is made of them. Above, a platform gives as many of the three as it has
organizations to give them through.

**So one platform is built on another by an organization.** The external platform's footing is the
three that one organization of the internal platform gives; its console stands on them alone. An
organization opened on the external platform has its compute and storage extended from a shadow
organization the external platform opens on the internal one through the internal platform's
`control` API, or from the user's own clouds. The internal platform's own extensions come from
third-party vendors and the author's machines.

Open, for the discussion that follows:

- Where an ordinary organization's own records are kept -- each tablet's log, the extent's records,
  its backing, its bundle -- which b8f35 keeps in a footing of its own, now that only the console
  stands on one: a database made of its extensions, placed by configuration. [B20]
- Where what manages extensions runs, perhaps in `control`. [B20]
- The database's sizes, a small one and a large one, and what each is made of. [B20]
- The new name for the storage's 16 MiB unit. [A10]
