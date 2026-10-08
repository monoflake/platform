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

In order, while the cluster still holds nothing anybody depends on -- what keeps data safe and the
operator practiced comes before the first app moves in --
[../architecture/databases.md](../architecture/databases.md):

1. **A week of `buf` emulated**, until 2026-10-14: it runs the database as arm64 by emulation since
   2026-10-07, and `amcheck`, which passed on all three that day, runs on every node at 14:00 UTC.
   Nothing moves in before the week is clean -- or before the work below is all done, if that is
   sooner, as the author allowed on 2026-10-07. Meanwhile, in parallel: the backups copied to a
   store on `rdu`'s and `buf`'s disks ("Toward services that keep nothing", 4), `ledger`'s move
   written and tested; and in infra, a new host reaching one node first, declarations uploaded
   apart, and host reading a changed `.env` -- all done on 2026-10-08, so `ledger` moves in then. `tyo` keeps a pgbench database of 150 MB until then,
   so there are indexes of size to check.
2. **`ledger` moves in**, the first of "Toward services that keep nothing", below. Its schema is the
   first a migration runner of the platform's would carry, if one is decided by then --
   [../issues/scheduling.md](../issues/scheduling.md), "Schema changes go through the platform".
3. **The cluster fails over by itself, with Patroni and etcd**, decided on 2026-10-08 in place of the
   operator's promote -- [../architecture/databases.md](../architecture/databases.md), "Where it
   runs, and which one writes":
   - **etcd on the five members**, `quorum`, a platform app of its own, each member's client and peer
     ports published to the tailnet, natively in each node's architecture; its heartbeat and
     election timeouts set for a quorum on three continents, its farthest pair, `gvx` and `sha`,
     about 380 ms apart: about 500 ms and 5 s. It answers
     only with a password, Patroni's from the secrets, since every container reaches the tailnet
     and a key written there moves the primary. Rolled out by hand, a member at a time, like the
     database.
   - **Patroni in the database's container**, the keeper's child, and Postgres Patroni's: the keeper
     renders Patroni's configuration and keeps answering host -- health, backups, `amcheck` -- and
     Patroni starts, follows, promotes and demotes. Its REST port is published to the tailnet, and
     everything but a read asks a password, `DATABASE_PATRONI_PASSWORD`.
   - **Asynchronous, as now**: a standby more than one WAL segment behind is never promoted
     (`maximum_lag_on_failover`), and the last seconds of writes may be lost, as is already accepted.
   - **The order stays**: `tyo` first, then `rdu`, then `buf`, as failover priorities; Patroni does
     not fail back by itself, so `tyo` is made primary again by a switchover, by hand.
   - **Five members, five voters**, decided on 2026-10-08: `tyo`, `rdu` and `buf` may lead, in that
     order; `gvx` in Sweden, arm64 natively on 970 MiB, and `sha` in Shanghai, x86 emulating arm64,
     are asynchronous standbys tagged `nofailover`. All five are etcd's members, so a quorum of three
     outlives any one region going -- Asia `tyo` and `sha`, the US `rdu` and `buf`, Europe `gvx`.
     `sha` holds the whole cluster in plain text inside mainland China, which the author accepted.
     The two join with Patroni, not before, each cloned from the latest base backup, and `gvx`
     runs Pigsty's smallest tuning.
   - **A node finds its own way back**: a standby that was away catches up from the primary or the
     archive, an old primary is rewound onto the new one, and one whose rewind fails, or a new node
     on an empty disk, is cloned again -- from WAL-G's latest base backup first, from the primary
     second.
   - **A primary that loses its lease stops taking writes**, demoted by Patroni when it cannot renew
     it in etcd. Containers have no watchdog, so the keeper is one: Postgres is stopped at once when
     Patroni exits, and both are killed when Patroni's REST stops answering for longer than the
     lease. The lease is Patroni's default, 30 s, with a loop of 10 and retries of 10, and that is
     the longest a fenced primary may still take writes.
   - **etcd down is not a primary down**: `failsafe_mode` keeps a leader that still reaches every
     member leading while etcd does not answer, as when all three members restart.
   - **`database promote` becomes `database switchover [node]`**, Patroni's own, for a planned move.
   - **Until the proxy, an app's URL names all three**, `target_session_attrs=read-write` over the
     cores' tailnet addresses, written by `database grant`, so a failover reaches the app without a
     grant; the proxy's single address replaces it.
   - **Settings are taken from Pigsty where they fit**: Patroni's timings and failover settings,
     etcd's, Postgres's tuning by the node's memory, and how a router asks Patroni which member is
     primary, as Pigsty v4.5.0's templates set them, Apache 2.0 -- https://github.com/pgsty/pigsty.
     Values are copied, not files: each lands in our own rendering, citing the template it came
     from, and what does not fit -- packages on the host, its monitoring, pgBackRest in place of
     WAL-G, native x86 Postgres -- is left. Decided on 2026-10-08.
   - **The running cluster is taken over in place**, `tyo`'s data directory becoming the first
     leader's, the standbys next, rehearsed in docker first, then on the nodes a node at a time.
4. **One address on every node for the database**, before a second app is given one: a small layer-4
   proxy of the platform's on every node, joined by host to every app's network, which passes each
   connection unaltered to the member Patroni's REST `/primary` answers `200` on, refusing new ones
   while none or two do. No pooling: each app's pool is its own, and pooling is weighed again when the
   cluster's connections near its `max_connections`. A failover or a major's switch then rewrites no
   URL and restarts no app.

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
