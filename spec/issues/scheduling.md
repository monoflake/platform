# Issues: scheduling and apps

What placing apps and their state leaves open. The rules over an entry are the index's; see
[issues.md](issues.md).

## How a Worker at the edge reaches Postgres on the nodes

A stateless Worker in any of Cloudflare's locations asking one Postgres on a node pays the distance
on every query. Workers VPC carries TCP, so a Worker can connect directly; Hyperdrive pools and
caches connections in front of a private database reached the same way. Which, and what is cached
at the edge, is undecided until a query is measured.

## The order the site leaves D1

The site's API keeps everything in D1 today. Moving it to the platform's Postgres is the largest
step of the site becoming an app on the platform; what moves first, and how the two run side by
side while it does, is undecided.

## What runs on one node until the platform's scheduler exists

Three services are on one node because a second copy would do the wrong thing, not because one is
enough. Each waits on the platform's scheduler, [../architecture/scheduling.md](../architecture/scheduling.md),
"Background work has two schedulers", which is not built:

- **`deployer`, on `tyo`.** It belongs on all three cores -- infra's `spec/architecture/nodes.md`,
  "Three nodes are the core, named by the author" -- but the hook tells every placement, so three
  copies would each deploy every run, and each keeps its own record of the last run deployed. One
  deploys under the lease and the others wait -- [../architecture/deployer.md](../architecture/deployer.md),
  "One deployer, on one node".
- **`probe`, on `rdu`.** Every copy would ask every check, multiplying what the rounds cost the
  gateway's free allowance, and each would keep its own history, so the gateway's `any` would answer
  a different one each time. Under the lease one asks and the rest stand by; or each node asks from
  where it is, which is the second place of [services.md](services.md), "A second place shares
  `checks` with the first".
- **`telemetry`, on `rdu`.** It reads its own node's meter and host, so a copy elsewhere describes
  another machine under the same scope. Reading every node's snapshot from the relay instead --
  [../architecture/relay.md](../architecture/relay.md) -- would make every copy answer the same, and
  then any node can run it.

Which comes first, the lease or telemetry reading the relay, is undecided.

## How often geo's data is rebuilt

geo's GeoNames and GeoLite2 are fetched as its image is built -- [../architecture/geo.md](../architecture/geo.md),
"GeoLite2 is fetched as the image is built" -- so they are as new as the last build: a push touching
geo, or `deploy.yml`'s run on the first of each month. MaxMind publishes GeoLite2 twice a week, so an
answer can be a month behind. Rebuilding more often redeploys the whole image to every node each
time, whether or not the data changed. Who triggers it is open too: GitHub's own schedule, as now, or
the platform's `cron` asking GitHub for a run, which needs a token in `cron` and, since `cron` runs on
every node, the platform's scheduler to ask once rather than seven times.

## How long an app keeps what it deleted

Every period a bucket has is seven days -- [../architecture/scheduling.md](../architecture/scheduling.md),
"Deleting releases a name, and the bytes go later": a deleted reference is restorable for seven days,
and unreferenced bytes are reclaimed seven days after. Apps will want their own: a user's trash kept
for a month, a cache's leftovers gone within the hour, and different parts of one app different
again. Where such a period is declared -- the app's `service.toml`, the bucket's layout, or a row the
app writes at run time -- and how finely, per app, per key prefix or per reference, is undecided.

## Exports to look at, kept apart from backups

A backup restores, and is kept beside its layer or below it -- the workspace's
`spec/architecture/layers.md`, "Managed from above, restored from below" -- and reaches three years
back. A second kind is wanted: an export of the platform's state, whole and readable without
restoring anything, encrypted to the author's key and kept wherever is convenient -- the author's
own scope among them -- to read how something was configured after it changed. It is taken by hand,
when the author asks, never on a schedule, and kept as long as the author keeps it. What it holds,
which key it is encrypted to and where it lands are undecided.

## Health does not say that archiving has stopped

On `tyo`'s first start, on 2026-10-07, the image had no CA bundle: WAL-G could not verify the store's
certificate and retried without end, so both the base backup and the archiving of WAL hung, and
`/health` answered healthy throughout -- `pg_stat_archiver` counts a failure only when the archive
command returns, and this one never did. The bundle is in the image now, and `S3_MAX_RETRIES=3` makes
an unreachable store fail within seconds rather than an hour, so a failure is counted and logged.
`/health` now says so and the backup job fails on it --
[../architecture/databases.md](../architecture/databases.md), "The container is Postgres and a keeper
of it". What is still open is anybody seeing it unasked: the probe cannot reach a socket on a node,
and the console shows a container's state, not what it answers, so a database that is up and not
backed up is visible only in the ledger's failed run, a day late at worst.

A base backup can also hang rather than fail: once it has begun, Postgres waits at its end for the
WAL it needs to be archived, so archiving that stops during a backup holds the job until `cron`'s
timeout. Seen on `buf` on 2026-10-07; the five minutes before the job refuses to start do not cover it.

## Schema changes go through the platform

Every app's migrations today run against the primary over its own `DATABASE_URL`, as the app
pleases. Logical replication does not carry them: a column added on the primary stops a
subscription that does not have it, and a table created there is never copied. The cluster no longer
needs a subscriber to span architectures -- [../architecture/databases.md](../architecture/databases.md),
"Where it runs, and which one writes" -- but a major's rolling upgrade is one, for as long as it runs,
and a friend's app the platform must answer for would want its schema known. A migration runner of the platform's would: an app hands it
its migrations, and it applies each to the primary and to every subscriber, in order, and records
which have run. It would also be where an app's schema version is known, which a major's upgrade and
the one address on every node -- [../todo/todo.md](../todo/todo.md), "The database" -- would read.
What an app hands it, how a migration that fails halfway is undone, and whether it is a service or
a step of deploying an app are undecided, and so is whether it is wanted before there are apps
of anybody else's: until then an app runs its own migrations, as `ledger` will, each change made in
two steps so the old version and the new survive it together.
