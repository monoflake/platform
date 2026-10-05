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
