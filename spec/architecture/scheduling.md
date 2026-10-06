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
device it is: a copy on it is a copy on that medium, and three copies are three media. A provider's
store is not counted that way, since what it promises already holds copies of its own -- how the two
are weighed against each other is [../issues/scheduling.md](../issues/scheduling.md).

A store is described by what it does, never by what it is made of: two SSDs, or an array of disks and
a lone one, differ more than a disk and an SSD do, and a provider's medium is not known at all.

**A bucket's access class is `standard` or `infrequent`**, the words S3 uses: how often its data is
read and how long the first byte may take, never the medium that answers. An article's pictures are
`standard`; an album's originals, read now and then, are `infrequent`. A store is fit for a class by
what it is measured to do.

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
