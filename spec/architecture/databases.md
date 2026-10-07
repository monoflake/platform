# Databases: the platform's Postgres, and the sidecar it replaces

**The platform runs one Postgres, on the three core nodes, and every scope's databases are in it.**
A scope is a bucket and the databases of the apps inside it -- [scheduling.md](scheduling.md), "A
scope is an organization, and only the boundary isolates" -- and this is where those databases are.
Until it is, an adopted program's database is the sidecar described after it.

## One cluster, and a scope is a role in it

**Every scope's databases are in one cluster, and the boundary between scopes is Postgres's own.**
Each scope is a role, each app a database that role owns, and no role is granted anything in another
scope's. One cluster is one Postgres on each core node rather than one per scope, which an organization
each, on a node of three gigabytes, could not afford. A scope that outgrows sharing moves to a cluster of
its own by logical replication, its apps none the wiser, since the boundary was already drawn.
Decided on 2026-10-07.

**An app is given its database by the operator**: one task makes the app's database and its login
under its scope's role, and writes `DATABASE_URL` into the app's `secret.env`. The URL names the
primary by its tailnet address.

## Where it runs, and which one writes

**`apps/data/database` runs on `tyo`, `buf` and `rdu`, and `tyo` is the primary, named by hand.**
The cluster cannot be placed by the platform's scheduler, whose leases are kept in it, so it is
pinned the way the core is -- infra's `spec/architecture/nodes.md`, "Three nodes are the core, named
by the author". `tyo` because it is a provider's machine held until 2036 with the most memory; `buf`
and `rdu` are its standbys.

- **Replication is streaming and asynchronous.** A commit waits for no standby: `tyo` to the eastern
  US is about 150 ms, which a synchronous standby would add to every write. A failover can lose the
  last seconds of writes, and that is accepted.
- **The port is published to the tailnet alone**, through the `peer` role with the port it names --
  infra's `spec/architecture/host.md`, "A role is asked for by the app and granted by the node". A
  standby reaches the primary there, and so does every app.
- **Failing over is a command, not a decision the cluster makes**: the operator promotes a standby,
  names it primary on all three, and the apps' URLs follow. Each node reads which node is primary
  from its configuration, so a primary that returns after being replaced is told what it now is
  rather than taking writes beside its successor. Failing over by itself needs the three cores to
  agree on who leads -- [relay.md](relay.md) -- and waits for that.

## The container is Postgres and a keeper of it

**A small program of ours is the container's process, and Postgres is its child.** host speaks
HTTP to what it runs -- a health path, and `cron`'s jobs -- and Postgres speaks only its own
protocol, so the program answers for it:

- **`/health`** says whether Postgres answers, whether this node is primary or standby, and how far
  a standby is behind.
- **On a first start** it makes the cluster on the primary, and on a standby copies the primary with
  `pg_basebackup` and follows it.
- **`/jobs/backup`**, which `cron` calls once a day, takes a base backup and lets go of what the
  tiers below no longer keep.

It answers on a socket in its own directory, as `apt` does, so the `cron` of each node reaches the
keeper of that node and no other -- a backup is the primary's to take and a standby's to skip -- and
the only port is Postgres's, published to the tailnet. The cluster beside the socket is the
database's user's alone, so the `cron` that is handed the directory reaches the socket and nothing
else in it.

## Backups are the data, kept off the cluster

**Every write is archived and every day is backed up, to an S3-compatible store, encrypted before
it leaves.** WAL-G pushes each segment of the write-ahead log within a minute of it filling or of a
minute passing, and the daily base backup beside it. That is what survives a `mistake` -- a table
dropped is restored to the moment before -- and losing every core at once.

**A rollback reaches three years back, and the further back the coarser:**

| Within         | Restored to                  | Kept                                 |
| -------------- | ---------------------------- | ------------------------------------ |
| 7 days         | any second                   | every daily base backup, and all WAL |
| 7 to 30 days   | the moment of each day       | each day's base backup, its own WAL  |
| 1 to 3 months  | the moment of each week      | one base backup a week               |
| 3 to 12 months | the moment of each month     | one a month                          |
| 1 to 3 years   | the moment of each half year | one every six months                 |

A base backup older than seven days is kept whole by keeping the WAL its own copying wrote, and
nothing between it and the next; WAL-G marks the ones the tiers keep and deletes the rest. Every
base backup is whole rather than a delta on the one before: the WAL is already the increment, a
delta would make each restore a chain that one lost link breaks, and at a few gigabytes the
difference in what is kept is cents a month. Deltas are weighed again when the compressed database
passes ten gigabytes. Decided on 2026-10-07.

- **What is deleted stays in a backup for up to three years**, and that is said plainly to anybody
  whose data the platform keeps.
- **A backup is restored by the major version of Postgres that took it**, so the image of every major
  a kept backup was taken by is kept as long as that backup is.
- **The store is named by its endpoint and credentials alone**, Backblaze B2 today: any
  S3-compatible bucket does, and moving is a change of four values. Its own versioning is off --
  [scheduling.md](scheduling.md), "A bucket is logical, a store is physical".
- **Encrypted with a key the provider never sees**, kept in the repository's secrets and, beside
  them, somewhere a lost laptop does not take with it: a backup that cannot be decrypted is not one.
- **A backup is proved by restoring it**, not by its upload succeeding.

These backups go to a store directly, not through a bucket of the platform's, whose index is in this
cluster -- the one thing below the buckets cannot be kept in them.

## Upgrades are pinned, reported, and rolled by hand

**Postgres, WAL-G and every image the cluster runs are pinned by tag and digest**, as every adopted
image is -- infra's `spec/architecture/host.md`, "An upstream image is adopted, not rebuilt". A newer
one upstream is reported, never taken by itself: moving the database moves every scope's data.

**The cluster is deployed by hand, a node at a time**, `rollout = "manual"` in its `service.toml`:
a run that builds it deploys nothing until the operator does, standby by standby and the primary
last, each answering healthy and caught up before the next. Deploying all three at once, as a run
deploys any other app, would restart the primary and both standbys together.

**A minor version is a new image and nothing else**: the data on disk is the same format, so it is
rolled as above, and rolled back the same way.

**A major version is rolled through the nodes by logical replication**, since a standby streams only
from a primary of its own major, while logical replication carries rows across majors:

1. One standby leaves the cluster, starts empty on the new major, and subscribes to the primary.
2. Once it has caught up, writes stop for a moment, sequences are carried over, and the apps'
   URLs move to it: it is the primary on the new major. Until the next step, moving them back is the
   way back.
3. The other standby is emptied and copied from the new primary, a standby on the new major.
4. So is the old primary, and the three are one cluster again.

While it runs no schema changes: logical replication carries rows, not DDL. A database too large to
copy quickly is converted in place on the first node instead, `pg_upgrade --link` and then
`pg_createsubscriber`, and the rest is the same. **A major is taken once it has reached its second
minor release, and at most once a year**; each is supported for five. The new major starts a new
backup chain under a prefix of its own, and the old one ages out by the tiers above with its image
kept.

**What an app connects to is the next step.** Its URL names the primary, so a failover or a major's
switch rewrites every app's URL and restarts it. A proxy on every node, answering on one address that
never changes and passing on to whichever node is primary, would make both invisible to the apps --
[../todo/todo.md](../todo/todo.md), "The database".

## The sidecar, for an adopted program until then

Our own services keep SQLite, one file each -- see [services.md](services.md). Some programs we
adopt rather than write keep nothing but Postgres; umami was why, and is not run any more -- see
web's `spec/analytics.md` -- and a ClickHouse driver built for OpenPanel went with it. For
such a program a database is a capability an app declares, run the way
[objects.md](objects.md) runs Versity: **one driver image, a sidecar per app over the app's own
directory**. The driver is shared, the data never is. Nothing runs one today, and the cluster above
replaces it.

### Declared by the app, run beside it

```toml
[postgres]
memory_mb = 192
```

**An app asks with `[postgres]` in its `service.toml`, and host runs `<app>-postgres` beside
it**, on the same terms as an objects sidecar:

- **The data is the app's**: the sidecar mounts `/data/apps/<app>/postgres/` and nothing else, so the snapshot a deploy takes holds the
  database, and a rollback with data puts it back.
- **It is on its app's network and no other**, reached by the app at the sidecar's name; no name
  is routed to it, and no other app is on it.
- **It lives and dies with its app** -- started before it and healthy within thirty seconds,
  stopped after it -- and an app that declares one while its driver is not deployed is refused.
- **It runs as the database's own user, never root**, over a directory host made and gave to that
  user before the first start, with a read-only root and the scratch paths the database writes as
  tmpfs. Its memory ceiling is the app's `memory_mb` for it, or the driver's default.
- **The app is handed the binding as its environment**, made once by host and kept in the app's
  `secret.env`, the sidecar given the same credentials as its owner:
  `DATABASE_URL`, `postgresql://<app>:<password>@<app>-postgres:5432/<app>`.
- **The password is made once and never rotated by host**: the URL in `secret.env` is the record
  of it, read back on every start, and a URL edited past reading fails the deploy rather than being
  replaced. Postgres takes its password only when it first makes the cluster, so a new one is set
  inside the database first and in the URL after.
- **A driver keeps its database's own port** -- 5432 -- outside the range an app's port is
  drawn from, since nothing but its app ever dials it.

The name `postgres` is reserved, and so is every `<app>-postgres`.

### The drivers

**`apps/data/postgres` is the official `postgres` image at a pinned major and digest**, adopted rather
than rebuilt, with settings for a small instance: `shared_buffers` 32 MB, no parallel workers,
twenty connections. Deploying it recreates each app's sidecar on the new image, one at a time, and
a failure puts every one back -- as `objects` does. A new major is not a deploy: Postgres needs its
data upgraded between majors, so a new major is a new driver, `postgres18`, and an app moves when
it is ready.
