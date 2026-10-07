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

In order -- [../architecture/databases.md](../architecture/databases.md):

- **The cluster on the core**: the backup store's five `BACKUP_S3_*` secrets, `mise run database
env`, `database` deployed to `tyo` and then its standbys, a backup taken and restored, and the
  backup key copied somewhere apart from the secrets.
- **Deployed by hand**: `rollout = "manual"` in its `service.toml` once host honors it -- infra's
  `spec/todo.md`, "An app may ask to be deployed by hand".
- **A newer pinned image is reported**: `outdated` reads the tag and digest every Dockerfile pins and
  says which have a newer one upstream, the way it reports packages, and moves none of them.
- **One address on every node for the database**: a proxy each node runs, which apps connect to and
  which passes on to whichever node is primary, so a failover or a major's switch rewrites no URL and
  restarts no app.

## Background work and packages

- **The platform's scheduler**, which runs a job once across the platform under a lease in Postgres
  -- [../architecture/scheduling.md](../architecture/scheduling.md), "Background work has two
  schedulers". It needs the cluster below first.

## The deployer

In order -- [../architecture/deployer.md](../architecture/deployer.md):

- **The deployer itself**, `apps/system/deployer` on `tyo`, and the hook's third receiver.
- **web admitted**: its `deploy.yml`, its webhook, `DEPLOY_SOURCES`, and the second GitHub token
  picked by owner in host and the deployer.
- **The console moved onto it**, dry first, then off Cloudflare's Git integration; then `aka`,
  `cdn`, `quota`, the gateway, and the site last.
