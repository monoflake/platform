# Scheduling: compute, storage and databases, placed by what they need

Where the platform is going, and none of it is built: an app says what it needs, and the platform
decides where that runs and where its data lives. The nodes it decides among, and the axes each is
declared by, are infra's `spec/architecture/nodes.md`.

## Two resources, and two kinds of data

**What the platform places on is compute and storage, and nothing else.** A node is compute; a store
is storage -- a disk at home, a TrueNAS pool, a provider's bucket. Each is declared by the same axes
as a node: tier, failure domain and expiry, with its capacity measured.

**Data is of two kinds, objects and databases, and an app has state by pairing compute with either
or both.** The two ask different things of a medium. A database writes small and often and waits on
every flush, so its live files are on a disk attached to the node it runs on; objects are written
whole and read from a distance, so any store takes them.

- **A node's disk holds either**: a database's live files, or objects through the store the node
  runs over it.
- **A provider's bucket holds objects alone**, a database's backups among them, never its live
  files. A backup is the data itself, kept like any other object of its class.

Decided on 2026-10-07, in place of a database whose durable state was objects in a store.

## An app declares its need, and the platform derives the place

- **Compute is N instances and the memory each takes, and keeps nothing**, as a Worker keeps
  nothing: whatever an app must remember is its scope's data. CPU is not declared: what is written
  here is TypeScript and Rust, whose cost is memory. An instance may run on any tier, `transient`
  included, and is started elsewhere when its node goes.
- **Storage is its scope's bucket**, reached through an S3-compatible API that does four things:
  put, get, delete and list. There are no versions; a key names its newest content.
- **A database is SQLite or Postgres.** An instance may keep a small SQLite inside itself for its own
  working state, which it can rebuild and which does not move with it; data that must outlive an
  instance, or is shared across apps, is in Postgres, a primary and its replicas.

## A bucket is logical, a store is physical, and either may be many of the other

**A bucket is the platform's, never a provider's: one entrance, holding a scope's names, the
content they point to and the stores that content is on.** The names are records in Postgres, the
content is addressed by its BLAKE3 hash -- the cid of [resource.md](resource.md) -- and the bytes are
on as many stores as the bucket's data asks, self-hosted, a provider's, or both. An app sees the
entrance and never a store behind it.

**A store is a place bytes are kept, and nothing more.** Whatever a provider offers above that --
versioning, lifecycle rules, replication of its own -- is left off, versioning above all: the
platform keeps its own history, in records and in bytes not yet reclaimed, and a provider's versions
of the same thing would be a second copy of it, billed by the byte and never read. Backblaze B2's is
turned off on every bucket held there; R2 has none to turn off.

**An object is kept at `{scope}/{ab}/{cd}/{cid}`, with no extension**, and is never overwritten,
since its key is its content. What type it is belongs to the reference that names it: the same bytes
named twice as two types are still one object. The fan-out is for a store that is a filesystem,
whose directories overflow -- web's `spec/architecture/data.md`, "Assets are addressed by their
content", where the site's own bucket keeps an extension this one drops.

**One store holds many buckets, and one bucket spans many stores.** How many copies a bucket keeps
follows how much its data matters, not how many disks there are. A store at home is offered as the
device it is: a copy on it is a copy on that medium, and three copies are three media.

A store is described by what it does, never by what it is made of: two SSDs, or an array of disks and
a lone one, differ more than a disk and an SSD do, and a provider's medium is not known at all.

**A bucket's access class is `standard` or `infrequent`**, the words S3 uses: how often its data is
read and how long the first byte may take, never the medium that answers. An article's pictures are
`standard`; an album's originals, read now and then, are `infrequent`. A store is fit for a class by
what it is measured to do.

## A bucket's stores are laid out by its owner, and what the layout survives is derived

**A layout is a tree of two kinds, written by whoever owns the scope**, its leaves stores:

- **`pool`** joins its members into one larger store, as RAID 0 joins disks: an object is on one
  member, chosen by room, and the pool holds what its members hold together.
- **`mirror`** keeps an object on every member, and says how many a write waits for. The rest are
  filled in behind it by the platform's scheduler, so what matters most can wait for two and what
  can be made again for one.

Three providers pooled, the third backed by one or two more, is a `pool` of A, B and a `mirror` of
C with its backups. Any member may itself be a `pool` or a `mirror`.

**What a layout survives is worked out from it, never typed beside it.** A durability in nines is a
figure nobody here can derive, and a count of copies has no reference -- three copies in one account
are one copy to an account that ends, while one copy in a provider's bucket already survives a dead
disk. What anybody can name is the failure:

| Failure   | Means                                        | Survived by                                                        |
| --------- | -------------------------------------------- | ------------------------------------------------------------------ |
| `medium`  | a disk dies                                  | two copies on two media, or one on a store redundant by itself     |
| `domain`  | an account ends, or the house goes           | copies in two failure domains                                      |
| `mistake` | a deletion, or a bug that rewrites good data | the platform's own history: a reference restorable, its bytes kept |

A store says two things a person knows: its failure domain, and whether it is redundant by itself --
a provider's bucket and a mirrored pool are, a lone disk is not. From those the platform reads a
layout and says which failures each part of it survives; a `pool` survives only what every member
does. No layout survives a `mistake`, since copies copy it; the platform's history does. S3's own
classes are framed the same way: its One Zone classes survive a disk and not the loss of a zone.

Decided on 2026-10-07, in place of a bucket that declared the failures it must survive and had its
copies derived: a layout across providers is what its owner reasons about, and the failures remain a
figure the platform states rather than one anybody types.

## A scope is the boundary, and only the boundary isolates

**A scope is a body of data: one bucket, and a Postgres holding the database of each app inside
it.** Compute keeps nothing, so everything with state is some scope's; an app runs wherever it is
placed and reaches its scope's bucket and its own database there. Inside a scope the apps share the
bucket; across scopes nothing is shared. There are three today:

| Scope      | Holds                                                                                         |
| ---------- | --------------------------------------------------------------------------------------------- |
| `infra`    | the nodes' own: their configuration, and how work is scheduled across them                    |
| `platform` | the accounts: every organization on the platform, the system's own and `canmi` the first user |
| `canmi`    | the author's organization: their sites, and the accounts those sites offer their own users    |

Each organization brought to the platform after is a scope of its own -- the workspace's
`spec/architecture/ship-cloud.md`, "Tenancy".

- **Content is deduplicated within a scope, never across one.** A shared store of bytes would tell
  one scope whether another holds a given file, would make deleting in one ask the other, and would
  leave no scope that could be taken away whole. The same bytes in two scopes are kept twice.
- **The platform's own data is a scope like any other, and no other scope's is the platform's.** The
  author's sites are in `canmi`, not in `platform` -- the dependency runs one way, as the
  workspace's `spec/architecture/layers.md` draws it.

## Names, content and copies are three layers

| Layer       | Answers                            | Is                                                      |
| ----------- | ---------------------------------- | ------------------------------------------------------- |
| **name**    | what this is, whose, and who reads | a reference: a key, its holder and the cid it points to |
| **content** | whether two are the same bytes     | the cid, within a scope                                 |
| **copies**  | where the bytes are, and how many  | placements on stores, kept matching the bucket's layout |

Deduplication happens at content and nowhere else. Copies are reconciled: a store that is lost is
replaced by another copy, and one whose expiry nears is emptied before it lapses.

## Every bucket is private, and a reference is what grants

**Nothing in a bucket is readable by being there**, the site's included: what the site serves today
is read by its Worker, which answers anyone only because there are no accounts yet.

**A reference is one row in the bucket's Postgres: a holder, a key, a content type and the cid it
points to.** The holder is a user, a group, or `public`. Whoever holds a reference to a cid may read
it, and nobody else. So content held by user A, by user B and by `public` reads for both of them and
for anyone; once `public`'s reference is revoked, user C reads nothing and A and B still do. The same
rows are what keeps the bytes alive, below: who may read a thing and what holds it cannot disagree,
because they are one table.

**Permission inside an app is the app's.** Its groups, its roles and which of its users may see what
are kept in the app's own database; the bucket knows holders and nothing finer. There are no versions
either: a key points at its newest cid, and an older one is kept only while something else holds it.

**The gateway serves bytes by the reference it is shown.** How somebody signed in is not its
concern.

- **A `public` reference** is answered without asking who is reading, and cached at the edge.
  Revoking one purges that address from the edge too, since a cache that is right forever for a
  content address is wrong the moment the right to read it ends.
- **Any other** carries a credential -- a header, or a cookie on the gateway's own domain, which is
  what a page's `<img>` and `<video>` can send -- holding the account and its session. However the
  reader signed in, the gateway checks that credential against the references to the cid and answers
  or refuses. A private answer is never kept in a cache another reader could be served from -- the
  gateway decides what the edge keeps, so it says so on every answer.

## Deleting releases a name, and the bytes go later

**A delete removes a reference and nothing else.** The row is kept, marked deleted, and can be put
back for a while; the bytes stay where they were. A cid becomes garbage only when no reference in its
scope -- live, or deleted and still restorable -- points at it, which deduplication makes the one
safe test: two references may share the bytes. They are counted by a table of references, never a
number kept beside the cid -- web's `spec/todo/milestones.md`, "Deleting removes one thing, and never
what it pointed at", is why.

**Every period is seven days for now**: a deleted reference can be put back for seven days, and a
cid nothing references is reclaimed seven days after. A period of its own for an app, or for one
part of an app, is open -- [../issues/scheduling.md](../issues/scheduling.md), "How long an app keeps
what it deleted".

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
bucket matches its layout again. How often a store is read through is its own, since a provider
charges for the reads.

## Background work has two schedulers

**A node's scheduler runs what belongs to that node, and the platform's runs what belongs to it
all.** A job says which it is.

- **The node's is `cron`** -- [cron.md](cron.md): a job runs on every node its service is placed on,
  once per node. Keeping a node's own system current is one -- [packages.md](packages.md).
- **The platform's runs a job once, whichever node does it**: reclaiming garbage, scrubbing copies,
  bringing copies back in line with what buckets declare, and a job of any service with more than
  one instance. One instance holds a lease the others can see, kept in the platform's Postgres, and
  runs the job while it holds it. It is not built yet.
