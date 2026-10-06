# Issues: scheduling

What [../architecture/scheduling.md](../architecture/scheduling.md) leaves open. The rules over an
entry are the index's; see [issues.md](issues.md).

## A job that runs once across the platform

`cron` runs a node's jobs on that node -- [../architecture/cron.md](../architecture/cron.md) -- so a
service placed on three nodes runs each of its jobs three times. Reclaiming, scrubbing and
reconciling copies must run once, whichever node does it, and so must a job of any service with more
than one instance. A job could say which it is, and the once-only kind then needs a lease that one
node takes and the others see, which Postgres could hold. Undecided.

## `apt` knows Debian alone

A node is Debian or Alpine -- infra's `spec/architecture/nodes.md` -- and
[../architecture/apt.md](../architecture/apt.md) starts two systemd units that run `apt-get`.
Alpine runs neither systemd nor apt: its packages are `apk`'s and its services OpenRC's. Whether
`apt` grows a second half for Alpine, under a name that is not a Debian tool's, or Alpine nodes keep
their packages some other way, is undecided.
