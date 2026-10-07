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
   written and tested, and the one address on every node; and in infra, a new host reaching one node
   first, declarations uploaded apart, and host reading a changed `.env`. `tyo` keeps a pgbench database of 150 MB until then,
   so there are indexes of size to check.
2. **`ledger` moves in**, the first of "Toward services that keep nothing", below. Its schema is the
   first a migration runner of the platform's would carry, if one is decided by then --
   [../issues/scheduling.md](../issues/scheduling.md), "Schema changes go through the platform".
3. **One address on every node for the database**, before a second app is given one: a proxy each
   node runs, which apps connect to and which passes on to whichever node is primary, so a failover or
   a major's switch rewrites no URL and restarts no app.

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
4. **A store on every node's disk**, S3 over its filesystem, and the backups copied each day to
   `rdu`'s and `buf`'s -- [../issues/scheduling.md](../issues/scheduling.md), "Backups are in one
   failure domain". Decided: an app `store` on both, its objects in host's Versity sidecar, whose
   daily job syncs B2's `database` prefix down with rclone, ciphertext only, deletions included so
   the tiers hold. Nothing is deleted when listing B2 fails or finds nothing, when B2 holds fewer
   than half the mirror's objects, or when any error occurs in the run. Its B2 key lists and reads
   the backup bucket alone.
5. **A scope's bucket, first version**: its index in the cluster, put, get, delete and list, laid out
   by `pool` and `mirror`, references, the sweep and the scrub on the scheduler.
6. **`shot` keeping nothing**: its queue in the cluster, its pictures in a bucket, its browsers on
   any node.
7. **`canmi`'s own accounts, and the site's bucket moved onto the platform's.**

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
