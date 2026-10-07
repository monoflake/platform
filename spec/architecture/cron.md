# `cron`: every scheduled job on a node, in one place

`apps/system/cron` calls the services on a node when their time comes. It does no work of its own: a job is
a service's route, and `cron` is what knows when to ask for it, what came of it, and when it last
did. Workers keep Cloudflare's own cron triggers; this is the node's. A job that has to run once
across the platform, whichever node runs it, is the platform's scheduler's, not this --
[scheduling.md](scheduling.md), "Background work has two schedulers".

**Every node runs a `cron` of its own, and it runs the jobs of the apps on its node alone.** A job
declared by an app placed on three nodes runs three times, once beside each instance, which is what
a job about a node's own state -- its packages, its copy of a database -- has to do.

## A job is declared by the service that does it

**A service lists its jobs in its `service.toml`**, beside what it answers, so a job and its route
change together:

```toml
[[schedules]]
name = "refresh"
cron = "0 4 * * *"      # or: every = "1m"
path = "/jobs/refresh"  # asked with POST, under the service's scope
catch_up = "once"       # a run missed while the node was down: "once" or "skip"
overlap = "skip"        # a run due while the last is still going: "skip" or "queue"
timeout = 300           # seconds before a run is called failed
spread = "week"         # optional: each node's runs shifted by its slot, see below
```

- **Every time is UTC.** A cron expression is read in UTC, every instant `cron` keeps or answers is
  UTC, and the console shows each in the reader's own zone.
- `every` takes seconds, minutes and hours (`30s`, `1m`, `6h`); `cron` takes the five-field form.
  Exactly one of the two.
- A service with jobs is reached one of two ways: through its `[api]` scope, or -- a service that
  answers on a Unix socket and on no port, as `apt` does -- on that socket, which host mounts into
  `cron` for that reason alone.

**`cron` answers on its port and has no scope**: `GET /schedules` -- every job, its next time and
its last run -- `POST /schedules/<service>/<name>/run` to run one now, and `.../pause` and
`.../resume`. Times are RFC 3339 in UTC. A scope names one service wherever it runs, and the gateway
sends it to any of its placements; seven `cron`s are seven tables, so asking one at random answers
nothing, and a service that is about its node is reached by its node instead -- see "Seen in the
console" below.

**host gives `cron` the table**: whenever an app is deployed or removed, host writes every app's
schedules to `schedules.json` in `cron`'s directory, through a temporary file and a rename, as it
tells the meter which container is which. `cron` reads it again when it changes; it asks host for
nothing, and host's API stays an operator's alone.

```json
{
	"jobs": [
		{
			"service": "geo",
			"name": "refresh",
			"cron": "0 4 * * *",
			"every": null,
			"path": "/jobs/refresh",
			"catch_up": "once",
			"overlap": "skip",
			"timeout": 300,
			"offset": 0,
			"reach": { "scope": "geo" }
		},
		{
			"service": "apt",
			"name": "update",
			"cron": "0 7 * * *",
			"every": null,
			"path": "/jobs/update",
			"catch_up": "once",
			"overlap": "skip",
			"timeout": 1800,
			"offset": 0,
			"reach": { "socket": "/sockets/apt/apt.sock" }
		}
	]
}
```

`offset` is seconds every run of the job is moved later by, which host works out from the job's
`spread` and the node's slot, below; `cron` adds it and knows nothing of either. `reach` is how
`cron` asks: a scope through Caddy, or a socket at the path host mounted it at --
each socket service's data directory at `/sockets/<service>` in `cron`'s container. **When that set
of services changes, host redeploys `cron`** so its mounts follow: a socket service deployed after
`cron`, in the same CI run or later, is reached without anyone asking.

## A weekly job is spread across the nodes, a day apart

**A job with `spread = "week"` runs on each node at its own time**, so an upgrade that goes wrong
goes wrong on one node, and a week still sees every node done. Its expression fires once a week, and
each node's runs are moved by its slot:

- **A node's slot is its position in infra's `nodes/nodes.toml`**, counted from zero, which
  `mise run node` writes into host's `.env` as `NODE_SLOT`. A node is appended to that file, never
  inserted, so adding one moves nobody else's day.
- **The first seven slots are seven days**: slot `n` runs `n` days after the expression's time.
- **Past seven, a day takes a second node two hours later**: slot `n` is `n mod 7` days and
  `2 * floor(n / 7)` hours after it. Twelve nodes a day fit before the hours run into the next day,
  so eighty-four nodes; what comes past that is decided when there are that many.

Decided on 2026-10-07; spreading by a hash of the node's name was rejected, since two names landing
on one day is exactly what the spread is for.

## A run is a request, and a task in the ledger

**At its time, `cron` asks `POST api.internal.ixc.one/<scope><path>` through Caddy** -- the private side,
which every container reaches -- or `POST <path>` on the service's socket, with the run's id in
`X-Task-Parent: cron:<id>`. A service that
records the work as a ledger task takes that as its `parent`, so the chain reads from the schedule
to everything the run set off.

**Every run is a ledger task of `cron`'s own**, kind `run`, its summary the job's service and name:
`queued` when it falls due, `running` when asked, `done` on a 2xx answer, `failed` on anything
else, on a timeout, or on no answer, with events for each step and the status and time taken. See
[ledger.md](ledger.md).

- **Missed runs**: on start, a job whose last run is older than its schedule allows runs once if
  it catches up, and waits for its next time if it skips. `cron` keeps each job's last run in its
  own SQLite, in its directory.
- **Overlap**: a run due while the last is still going is skipped, recorded as a skipped run, or
  queued behind it, as the job says.

## Seen in the console

The console's Schedules page is to list every job -- its node, its service, its schedule, when it
runs next, how its last run went, read from the ledger -- and run one now; it waits on the console's
own todo. **It reads each node's `cron` through that node's door, as it reads the node's host**,
infra's `spec/architecture/host.md`, "host has no interface on the node, and a door Caddy keeps". **Pausing a job is the repository's
change**, as every setting the console changes is to be (infra's `spec/architecture/host.md`, "One name inside, and a
domain label outside"): until the bot that writes it exists, a pause is `cron`'s own, held until
`cron` restarts, and shown as such.
