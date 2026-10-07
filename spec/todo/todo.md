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

## Background work and packages

- **The platform's scheduler**, which runs a job once across the platform under a lease in Postgres
  -- [../architecture/scheduling.md](../architecture/scheduling.md), "Background work has two
  schedulers". It needs Postgres off the node at home first.
- **`apk`, Alpine's agent behind the package interface** -- [../architecture/packages.md](../architecture/packages.md).

## The console's depth

What the console's pages draw around today, each waiting on the service that holds the fact --
[../architecture/console.md](../architecture/console.md):

- **The meter reports a node's architecture** in its machine info; the console reads it from the
  kernel release meanwhile, and Alpine's `-virt` kernels give none.
- **The hook keeps every `workflow_run` event**, queued and in progress as well as completed, with
  the commit message, branch and actor, so the queue shows a run before any node sees it.
- **Host stamps each stage of a deploy**, not only the last one reached, so a run's timeline has a
  bar per stage.
- **Host answers events by run**, so a run older than a node's last 500 events stays in the queue
  and in the 30-day figures.
- **Host records the repository an app was built from**, on the app and on each deploy event, so
  the console's scope of an app is a fact it reads rather than a list of names it keeps beside
  infra's and the platform's apps.
- **One list of the ranges**, `1h` to `30d`, in place of the three the pages carry, and run grouping
  moved out of `lib/server/` so the live panel stops keeping its own copy.

## The deployer

In order -- [../architecture/deployer.md](../architecture/deployer.md):

- **The deployer itself**, `apps/system/deployer` on `tyo`, and the hook's third receiver.
- **Worker artifacts**: `.mise/tasks/worker` in the platform and web, and `deploy.yml` emitting
  `worker-<app>`.
- **web admitted**: its `deploy.yml`, its webhook, `DEPLOY_SOURCES`, and the second GitHub token
  picked by owner in host and the deployer.
- **The console moved onto it**, dry first, then off Cloudflare's Git integration; then `aka`,
  `cdn`, `quota`, the gateway, and the site last.
