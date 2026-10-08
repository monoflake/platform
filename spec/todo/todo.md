# Todo: what is decided and waiting

Work the platform has agreed to and not finished. Open questions are
[../issues/issues.md](../issues/issues.md) and the direction is [../roadmap.md](../roadmap.md); how the
three divide the work is the workspace's `spec/planning.md`.

## The gateway's milestones

[milestones.md](milestones.md), E, is the agreed order. Waiting now: **E7**, the firewall's
whitelists generated from the table, and **E13**, the cleanup pass over what the move left behind.

## The service domains answer at their apexes

What web's `spec/architecture/landing.md` decides, the hosts' half of it:

- **`symlink.si` gives its host to a static site on the CDN and keeps the names on a route.** The
  apex gets a record proxied by Cloudflare, `/` and everything that is not a name reach the site, and
  the names the alias layer answers stay on the gateway's Worker as a route laid over the host -- in
  place of the custom domain that takes the whole host today, see
  [../architecture/gateway.md](../architecture/gateway.md), "The gateway declares its hosts in its
  `wrangler.jsonc`".
- **`monoflake.net` sends to `monoflake.com`**, not to the site: its redirect in
  `rules/monoflake.net` changes its target.
- **`monoflake.com` and `ixc.one` get their apex records**, so the page each is to answer can be
  reached; `www.ixc.one`'s redirect to its apex leads nowhere until then.

## The database

Whenever there is room: **a newer pinned image is reported** -- `outdated` reads the tag and digest
every Dockerfile pins and says which have a newer one upstream, the way it reports packages, and moves
none of them.

## Toward services that keep nothing

In order, each deployed and proved before the next -- [../architecture/scheduling.md](../architecture/scheduling.md):

1. **`ledger` in the cluster**, in `platform`: its SQLite on `rdu` becomes its database there, and it
   runs on all three cores. The first app given a database, and so the proof of `database grant`.
2. **The platform's scheduler**, a lease in the cluster: the deployer on the three cores, and the
   probe and telemetry off the one node each is on --
   [../issues/scheduling.md](../issues/scheduling.md), "What runs on one node until the platform's
   scheduler exists".
3. **The platform's identity, first part**: every app given a `service:<app>` credential when it is
   deployed -- [../architecture/scheduling.md](../architecture/scheduling.md), "Who asks is a
   principal, and an issuer vouches for it".
4. **A store on every node's disk**, S3 over its filesystem. `rdu` and `buf` have theirs, holding
   the backups' daily mirror since 2026-10-08 --
   [../architecture/databases.md](../architecture/databases.md), "Backups are the data, kept off
   the cluster"; the other nodes' follow when a bucket's layout first names them.
5. **A scope's bucket, first version**: its index in the cluster, put, get, delete and list, laid out
   by `pool` and `mirror`, references, the sweep and the scrub on the scheduler.
6. **`shot` keeping nothing**: its queue in the cluster, its pictures in a bucket, its browsers on
   any node.
7. **`canmi`'s own accounts, and the site's bucket moved onto the platform's.**

## Placement is declared, not listed

Decided on 2026-10-08, so a node can join without an edit to every app that runs everywhere --
[../issues/scheduling.md](../issues/scheduling.md), "A node is added by hand in seven places":

- **An app declares where it may run, never which nodes**: a group -- `core`, `home`, `datacenter`,
  or `any` -- and, where it matters, a place by country or region, and host deploys it on every
  node that matches. `ledger` is the United States and `home`, which is `rdu` today and any
  machine at home in the US after it.
- **The core is the nodes with the most room and the best path to Cloudflare**, not the ones that
  hold Postgres: `rdu`, `tyo` and `buf`. `sha`, with 15 GiB, was measured and passed over: its
  tunnel lands in Los Angeles, connecting to Cloudflare in about 270 ms against `buf`'s 28 ms, and
  it downloaded from Cloudflare at 84 KB/s against `buf`'s 52 MB/s.
- **The database names its members apart from the core**, as it does today.

## Background work and packages

- **The platform's scheduler**, which runs a job once across the platform under a lease in Postgres
  -- [../architecture/scheduling.md](../architecture/scheduling.md), "Background work has two
  schedulers" -- second of "Toward services that keep nothing", below.

## The deployer

In order -- [../architecture/deployer.md](../architecture/deployer.md):

- **The deployer itself**, `apps/system/deployer` on `tyo`, and the hook's third receiver.
- **web admitted**: its `deploy.yml`, its webhook, `DEPLOY_SOURCES`, and the second GitHub token
  picked by owner in host and the deployer.
- **The console moved onto it**, dry first, then off Cloudflare's Git integration; then `aka`,
  `cdn`, `quota`, the gateway, and the site last.
