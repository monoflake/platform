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
