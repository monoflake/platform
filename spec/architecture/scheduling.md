# Scheduling: compute, storage and databases, placed by what they need

Where the platform is going, and none of it is built: an app says what it needs, and the platform
decides where that runs and where its data lives. The nodes it decides among, and the axes each is
declared by, are infra's `spec/architecture/nodes.md`.

## Two resources, and a database made of both

**What the platform places on is compute and storage, and nothing else.** A node is compute; a store
is storage -- a disk at home, a TrueNAS pool, a provider's bucket. Each is declared by the same axes
as a node: tier, failure domain and expiry, with its capacity measured. A database is not a third
resource: it is a process on a node whose durable state is objects in a store.

## An app declares its need, and the platform derives the place

- **Compute is N instances and the memory each takes.** CPU is not declared: what is written here is
  TypeScript and Rust, whose cost is memory. An instance that keeps nothing may run on any tier,
  `transient` included, and is started elsewhere when its node goes.
- **Storage is a bucket**, reached through an S3-compatible API, with how many copies it keeps and
  across how many failure domains. Public content keeps at least one copy where the CDN reads it.
- **A database is SQLite or Postgres.** An instance may keep a small SQLite inside itself for its own
  working state, which it can rebuild and which does not move with it; data that must outlive an
  instance, or is shared across apps, is in Postgres, a primary and its replicas.

## A bucket is logical, a store is physical, and either may be many of the other

**One store holds many buckets, and one bucket spans many stores.** How many copies a bucket keeps
follows how much its data matters, not how many disks there are. A store at home is offered as the
device it is: a copy on it is a copy on that medium, and three copies are three media.

A store is described by what it does, never by what it is made of: two SSDs, or an array of disks and
a lone one, differ more than a disk and an SSD do, and a provider's medium is not known at all.

**A bucket's access class is `standard` or `infrequent`**, the words S3 uses: how often its data is
read and how long the first byte may take, never the medium that answers. An article's pictures are
`standard`; an album's originals, read now and then, are `infrequent`. A store is fit for a class by
what it is measured to do.

## A bucket declares the failures it must survive, and its copies are derived

**Neither a count of copies nor a durability in nines is declared.** Nines are a figure nobody here
can derive, so a sum of them is as precise as the guess typed in; and a count has no reference --
three copies in one account are one copy to an account that ends, while one copy in a provider's
bucket already survives a dead disk. What anybody can name is the failure:

| Failure   | Means                                        | Survived by                                                    |
| --------- | -------------------------------------------- | -------------------------------------------------------------- |
| `medium`  | a disk dies                                  | two copies on two media, or one on a store redundant by itself |
| `domain`  | an account ends, or the house goes           | copies in two failure domains                                  |
| `mistake` | a deletion, or a bug that rewrites good data | history kept for a while: snapshots or versions                |

A bucket lists the failures it survives, and the platform derives the copies. A store says two things
a person knows: its failure domain, and whether it is redundant by itself -- a provider's bucket and
a mirrored pool are, a lone disk is not. Copies alone never survive a `mistake`, since they copy it.
Derived data, which can be made again, survives nothing and keeps one copy. S3's own classes are
framed the same way: its One Zone classes survive a disk and not the loss of a zone.

## A scope is the boundary, and only the boundary isolates

**Data is shared inside a scope and isolated between scopes.** A scope is a set of apps that belong
together -- the author's own sites are one, a site built for somebody else and its own users another.
Inside one, the apps share their buckets and their Postgres; across one, nothing is shared.

- **Content is deduplicated within a scope, never across one.** A shared store of bytes would tell
  one scope whether another holds a given file, would make deleting in one ask the other, and would
  leave no scope that could be taken away whole. The same bytes in two scopes are kept twice.
- **The platform is below every scope**, and no scope's data is the platform's. The author's sites
  are a scope on the platform, not part of it -- the dependency runs one way, as the workspace's
  `spec/architecture/layers.md` draws it.

## Names, content and copies are three layers

| Layer       | Answers                             | Is                                                           |
| ----------- | ----------------------------------- | ------------------------------------------------------------ |
| **name**    | what this is, whose, and from where | the rid and its record -- [resource.md](resource.md)         |
| **content** | whether two are the same bytes      | the cid, within a scope                                      |
| **copies**  | where the bytes are, and how many   | placements on stores, kept matching what the bucket declared |

Deduplication happens at content and nowhere else. Copies are reconciled: a store that is lost is
replaced by another copy, and one whose expiry nears is emptied before it lapses.

## Every object has a record, and access is decided on it

**Content-addressed bytes need a database beside them.** A cid says nothing about where the bytes
came from, so every object has a record: its scope, the app that wrote it and, once there are
accounts, the user, with who may read it. Permission is granted on the name and never on the cid,
since one cid may stand behind two names that are not equally readable.

**The gateway serves a public object by its content address and a private one by its record.** What
it must do is tell the two apart and judge the second correctly; how somebody signed in is not its
concern.

- **Public** is answered without asking who is reading, and cached at the edge for as long as the
  bytes exist, since a content address never changes what it names.
- **Private** carries a credential -- a header, or a cookie on the gateway's own domain, which is
  what a page's `<img>` and `<video>` can send -- holding the account and its session. However the
  reader signed in, the gateway checks that credential against the object's record and answers or
  refuses. A private answer is never kept in a cache another reader could be served from -- the
  gateway decides what the edge keeps, so it says so on every answer.

## Deleting releases a name, and the bytes go later

**A delete removes a name from the index and nothing else.** The record is kept, marked deleted, and
can be put back for a while; the bytes stay where they were. A cid becomes garbage only when no name
in its scope -- live or deleted and still restorable -- points at it, which deduplication makes the
one safe test: two names may share the bytes.

**Each store says how it lets garbage go**:

- **`lazy`** keeps it until the space is wanted. A disk of our own costs nothing to keep full, so
  garbage there counts as free space and is evicted, oldest first, only when something new needs
  room -- and until then it can still be found.
- **`prompt`** lets it go after a grace period, by a background job, never in the request that
  deleted it. A provider's store charges for every byte kept.

So every layer has its own way back: a name is restored from the index, bytes from a store that has
not reclaimed them, and what a bucket keeps for `mistake` beneath both.

## Every copy is checked, and a bad one is replaced

**A copy that is recorded is not a copy that is there.** The worst loss is the one found on the day
the data is needed, so a scrub reads every copy on a schedule, as ZFS does a pool, and a content
address makes the check exact: the bytes hash to their cid or they are bad. A bad or missing copy is
struck from the record and copied again from a good one, onto the same store or another, until the
bucket survives what it declared. How often a store is read through is its own, since a provider
charges for the reads.

## Background work is jobs, run by the one timer

Reclaiming garbage, scrubbing copies and bringing copies back in line with what buckets declare are
jobs, declared and run as every other is -- [cron.md](cron.md) -- beside the jobs that keep each
node's own system current, [apt.md](apt.md). They are the platform's, not a node's: each must run
once across the platform rather than once on every node, which `cron` does not yet do --
[../issues/scheduling.md](../issues/scheduling.md).
