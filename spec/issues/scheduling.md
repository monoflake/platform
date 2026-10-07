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

## Backups are in one failure domain

Every backup of the platform's Postgres goes to one Backblaze B2 account --
[../architecture/databases.md](../architecture/databases.md), "Backups are the data, kept off the
cluster" -- so the account ending loses every backup at once, which is the `domain` failure of
[../architecture/scheduling.md](../architecture/scheduling.md). The stores a node's own disk offers
over S3 -- `rdu`'s, in the house, first -- would close it, a copy of the backups' ciphertext taken
from the first store each day: WAL-G's own second storage takes over when the first fails rather
than keeping a copy in both. It waits on those stores existing.

## A timeline's history can go with the WAL around it

WAL-G keeps a permanent base backup whole by keeping the WAL segments its own copying wrote, and
deletes every other segment before the delete point -- the timeline history files among them, which
are not numbered segments. A base backup taken after a failover, on timeline two or later, then
restores only if the history leading to its timeline is still in the store. Every backup proved so
far was on timeline one. Keeping the history files out of the deletion -- copied beside the backups
under a prefix WAL-G does not prune, or never deleted at all, since they are a few hundred bytes each
-- would close it, and needs a restore after a real failover to prove.

## An unreachable backup store holds the job for an hour

WAL-G retries a store it cannot reach rather than failing, so a backup job against a store that is
down waits until `cron`'s timeout of an hour and is recorded failed then, not at once. Nothing is
lost -- the job deletes nothing until every step before has succeeded -- but the failure is an hour
late and the job holds its slot for it. A shorter timeout of WAL-G's own would answer sooner; what
it should be, against a base backup that may take minutes once the database is large, is undecided.

