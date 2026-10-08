# `ledger`: every task any service was asked to do

`apps/data/ledger` is the one record of the work the platform's services take on: a capture `shot`
queued, and later whatever a scheduled job, a conversion or an import runs. A service keeps what it
needs to do the work; the ledger keeps that it was asked, by whom, how it went, and keeps it for
good. It is written to by every service and read by the console, so a task whose result is long gone
-- a picture rolled out of `shot`'s store -- is still a row somebody can find.

## A task, and the events that make it up

**The ledger's model is a task and the events inside it, in order.** A service's log lines lose
both: which task a line belongs to, and where among its lines it falls once several tasks interleave.
Here every event belongs to one task and carries its place in it.

A **task** is one thing a service was asked to do:

| Field                                   | What it is                                                           |
| --------------------------------------- | -------------------------------------------------------------------- |
| `service`, `id`                         | the service's name and its own id for the task                       |
| `kind`                                  | what was asked, in the service's words: `capture`                    |
| `state`                                 | `queued`, `running`, `done` or `failed`                              |
| `caller`                                | `public`, marked by the gateway, or `ours`                           |
| `parent`                                | the task that asked for this one, `{ service, id }`, when a task did |
| `asked_at`, `started_at`, `finished_at` | RFC 3339 instants, the last two once they happen                     |
| `summary`                               | a small JSON object the service chooses: for `shot`, the page's URL  |
| `detail`                                | why it failed, in the service's words, when it did                   |

An **event** is one step of a task, appended and never changed:

| Field                    | What it is                                                                            |
| ------------------------ | ------------------------------------------------------------------------------------- |
| `service`, `task`, `seq` | the task it belongs to, and its place there: a number that only grows within the task |
| `at`                     | when, an RFC 3339 instant                                                             |
| `stage`                  | the step, in the service's words: `resolving`, `loading`, `rendering`, `storing`      |
| `level`                  | `info`, `warn` or `error`                                                             |
| `message`                | one line for a person                                                                 |
| `data`                   | a small JSON object, when the step has figures worth keeping                          |

**Order is `seq`, never arrival.** The client numbers a task's events as the service makes them --
the moment in nanoseconds, or one past the task's last number when the clock has not moved on, so a
service restarted mid-history never reuses a number -- and so
a batch sent late, a retry, or two batches crossing change nothing about the order the ledger
answers with. A task's state changes are events too -- `queued`, `running`, `done`, `failed` as
stages -- and the task's row is kept in step with them in the same transaction.

**`parent` ties a chain together across services**: a scheduled job that asks `shot` for a capture
is the capture's parent, so one look follows the work from what started it to everything it
started.

## Pushed to, never asking

**A service tells the ledger; the ledger never asks a service.** `POST /events` takes a batch, each
item either a task -- its whole record, kept as the latest one sent -- or an event, kept once by its
`(service, task, seq)` so a batch sent twice is harmless. `PUT /tasks/{service}/{id}` stays for a
single task.

The ledger stamps a task's `updated_at` itself. **A later `asked_at` always replaces what is kept**:
it is the same task asked again, as `shot` asks a failed capture again under its id. Within one
asking, a record without a `finished_at`, or with an older one, does not replace one that has it,
so a late `running` cannot undo a `done`. An event of a later asking follows the earlier asking's
events in `seq`, since its numbers are later moments.

**Delivery is the service's to retry, and never its to wait on.** `libs/ledger` is the client every
Rust service uses: a task or an event is handed to it and the call returns at once; a background
task sends them in batches, and holds what could not be sent in a bounded queue, oldest dropped
first, trying again with backoff. A ledger that is down costs records, never a capture.

**It is reached through Caddy, as a scope that is never public**: services write to
`api.internal.ixc.one/ledger`, which every container reaches, since Caddy admits Docker's private range
there. Like every scope it is on `api.canmi.app` too, where Access stands in front and our Workers
reach it over VPC; it is in the gateway's table as a private scope, so a node's private side can
send a write on to it from another node with `INTERNAL_TOKEN`, and the public never reaches it. Nothing asks for a
token, as nothing on the private side does; host is the exception, and the ledger is not host.

## Read by the console

`GET /tasks` lists tasks newest first, a page at a time -- each item carries its `cursor`, and
`before=<cursor>` of the last one asks for the next page, `limit` at most 500 -- narrowed by `service`, `state`, `kind`, `caller` or `parent`;
`GET /tasks/{service}/{id}` is one, with its events in `seq` order and the tasks it is the parent
of. The console's Tasks page is to read these: a list, and a task as a timeline -- each step, how long it
took, where it failed, what started it and what it started. The answer is always the envelope. A
query that does not read is forgiven rather than refused: a cursor that does not parse starts from
the top, a filter naming no known value matches nothing, and a limit out of range is brought into
it.

**The list is ours alone.** A record carries what somebody asked for -- a capture's URL is someone
else's browsing -- so no route of a public scope lists records; a public caller reads its own task
by the id it was given, from the service that made it.

## Counted for telemetry

`GET /counts?hours=` answers how many tasks each service was asked for in each of the last `hours`
whole hours and the one under way -- 1 to 168, 24 when absent -- by `asked_at`, as
`[{ service, hour, state, count }]`, `hour` the RFC 3339 instant it starts, oldest first. It says
nothing of a task but its service, when it was asked and how it stands, which is what `telemetry`
may publish. See [telemetry.md](telemetry.md).

## Kept for good, in the platform's Postgres

**Nothing is ever deleted, tasks or events.** A task is a few hundred bytes and an event less; a
year of captures at thousands a day, each a handful of events, is some hundreds of megabytes.

**The ledger's history is `platform_ledger` in the platform's cluster**, owned by the `platform`
role and reached by the `DATABASE_URL` that `mise run database grant platform ledger` writes --
[databases.md](databases.md), "One cluster, and a scope is a role in it". So it is backed up,
mirrored and failed over as the cluster is, and the ledger keeps nothing on its node.

- **Two tables on their natural keys**: tasks keyed by `service` and `id`, events by `service`,
  `task` and `seq`, so no key is ever minted. Times are nanoseconds in a `bigint`, since the cursor
  and its ties need more than `timestamptz`'s microseconds; a record and an event's data are
  `jsonb`; the key columns are `COLLATE "C"`, so the order is bytewise whatever the cluster's
  locale.
- **Which write wins is decided in SQL**, one `INSERT ... ON CONFLICT DO UPDATE ... WHERE` per task,
  so it holds however many ledgers write at once; a batch is still one transaction.
- **Its schema moves by migrations the ledger runs itself**, each at start under one advisory lock,
  in its own transaction with its row in `ledger_migrations`. A migration is an expand or a
  contract, and a test refuses an expand that drops, renames, retypes, adds `NOT NULL` or truncates
  anything; a runner for every app is [../issues/scheduling.md](../issues/scheduling.md), "Schema
  changes go through the platform".
- **Its SQL is tested against a real Postgres 18**: a service in CI, and a throwaway one in docker
  locally; without one the SQL tests say so and pass over themselves, and in CI that is a failure.
- **The SQLite it was kept in is read once, by `ledger import <path>`**, which copies every task as
  kept and every event, any schema it ever had, and copies nothing twice when run again.

Until it moves in, the ledger deployed on `rdu` is the SQLite one, `ledger.db` in its own directory,
and its rollout is by hand so the new one is not deployed before its database exists --
[../todo/todo.md](../todo/todo.md), "The database".
