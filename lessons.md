# Lessons

Facts taken from the old system, and from the vendors the model stands on, each answering a question
the model asked, each with its source. Facts only, never a structure to copy. See `spec/process.md`.

## Cloudflare, read 2026-10-17

**A Worker cannot run code it is handed at run time.** "For security reasons, the following are
not allowed: `eval()`, `new Function`, `WebAssembly.compile`, `WebAssembly.compileStreaming`,
`WebAssembly.instantiate` with a buffer parameter, `WebAssembly.instantiateStreaming`."
Asked by checklist B6. Source: https://developers.cloudflare.com/workers/runtime-apis/web-standards/

**The Worker Loader binding runs code handed to it in an isolate of its own.** Asked by B6.
Source: https://developers.cloudflare.com/dynamic-workers/api-reference/index.md and the pages
beside it.

- `env.LOADER.get(id, callback)` returns a stub at once and "caches isolates by ID"; the callback
  supplies the code only when the isolate is not loaded, so it must return the same code for the
  same id. `load(code)` creates a new Worker each call and caches nothing.
- The code is a map of modules: `js`, `cjs`, `py`, `text`, `data`, `json`, and `wasm` given as an
  `ArrayBuffer`.
- `globalOutbound: null` makes `fetch()` and `connect()` throw; set to a service binding, every
  outbound request goes through it. `env` is chosen by the caller: structured-clonable values and
  service bindings.
- CPU time and subrequests may be limited per Worker, `cpuMs` and `subRequests`; past either it
  throws at once. Each defaults to the plan's.
- At most 4 distinct dynamic Workers with requests in flight per request, 10 per Durable Object;
  several requests to one count once.
- Workers Paid only. Included: 1,000 unique dynamic Workers a month, then $0.002 per dynamic Worker
  per day, with requests and CPU time at Workers Standard rates. Neither beta nor general
  availability is stated on the pricing page.

**D1's limits** on Workers Paid, asked by B13. Source:
https://developers.cloudflare.com/d1/platform/limits/

- 50,000 databases an account, raised on request; 10 GB a database; 1 TB of D1 in all an account.
- 2 MB a row, string or BLOB; 100 KB a statement's text; 100 bound parameters; 30 seconds a query;
  1,000 queries a Worker invocation.
- Point-in-time recovery for 30 days.

**D1 is reached from outside Cloudflare through a Worker, not its REST API.** D1's REST API "is
best suited for administrative use as the global Cloudflare API rate limit applies"; that limit is
1,200 requests per five minutes per user, every call blocked for five minutes past it. Asked by B13.
Sources: https://developers.cloudflare.com/d1/tutorials/build-an-api-to-access-d1/ and
https://developers.cloudflare.com/fundamentals/api/reference/limits/. How long a query from a
machine outside Cloudflare takes through a Worker is not published, and is to be measured.

**D1 runs a batch as one transaction, and has no transaction across calls.** "Batched statements
are SQL transactions"; a statement that fails "aborts or rolls back the entire sequence", and "each
statement in the list will execute and commit, sequentially, non-concurrently". Outside a batch
D1 "operates in auto-commit". Its page says nothing of `BEGIN` and `COMMIT`; developers report
them refused, so a transaction that reads and then decides is not offered. Asked by B16. Sources:
https://developers.cloudflare.com/d1/worker-api/d1-database/ and, for the refusal, a report at
https://github.com/drizzle-team/drizzle-orm/issues/2463.

**Where a D1 database runs is hinted, never promised**: `wnam`, `enam`, `weur`, `eeur`, `apac`,
`oc`, and "it will run in the nearest possible location (by latency) to your preference"; a
jurisdiction, `eu`, `fedramp` or `us`, is set at creation and never changed. Read replicas in every
region are reached only through the Sessions API, sequentially consistent within a session by a
bookmark; without it every query goes to the primary. Asked by B16. Sources:
https://developers.cloudflare.com/d1/configuration/data-location/ and
https://developers.cloudflare.com/d1/best-practices/read-replication/

**Where a Worker runs can follow what it calls**: a placement hint, `region` for a major cloud's
region or `host` and `hostname` for one elsewhere, runs it nearest that; Smart Placement moves only
fetch handlers, never RPC methods. Neither page says it follows a D1 database. Asked by B16.
Sources: https://developers.cloudflare.com/changelog/post/2026-01-22-explicit-placement-hints/ and
https://developers.cloudflare.com/workers/configuration/smart-placement/

No measured latency of a write to D1 from a Worker is published; Cloudflare's own figures are for
reads, and are to be measured for ourselves.

**A Worker's limits** on Workers Paid, asked by B13. Source:
https://developers.cloudflare.com/workers/platform/limits/

- 128 MB of memory.
- CPU time 30 seconds by default, up to 5 minutes set; waiting on the network is not counted.
- 10,000 subrequests a request.
- A request's body is limited by the account's plan: 100 MB on Free and Pro, 200 MB on Business,
  up to 5 GB on Enterprise.

## Cloudflare's free plan, measured 2026-10-17

Measured on the `monoflake` account, on the free plan, from two machines a provider runs, one in
Tokyo and one in Singapore, against a Worker over D1, one keep-alive connection a run. Asked by
B16. Times are the median; "in the Worker" is what the Worker timed around its call to D1.

**Free-plan traffic does not always reach the nearest location.** Which location a connection
lands in is chosen as it is made, and runs of the same machine landed far apart: Tokyo's in NRT
and PDX, Singapore's in SIN, HKG, NRT and CDG. Landed far, a write took 200 to 550 ms from the
machine instead of 40.

**Where the database is matters less than where the request lands.** Landed in NRT:

| Operation               | D1 hinted `apac`, in the Worker | D1 hinted `oc`, in the Worker |
| ----------------------- | ------------------------------- | ----------------------------- |
| a write of one row      | 26 to 37 ms                     | 143 to 145 ms                 |
| a read from the primary | 18 to 23 ms                     | 138 to 143 ms                 |
| a read from a replica   | 25 to 28 ms                     | not measured                  |

D1's own time for a statement was about 0.2 ms; the rest is the way between the Worker and the
database. A one-row write from Tokyo took 40 ms from the machine, 9 ms of it reaching the Worker.

**Read replication is offered on the free plan**, turned on by the REST API's
`{"read_replication": {"mode": "auto"}}`, and is reached through the Sessions API; landed in NRT
it was no faster than the primary, which `apac` placed near Tokyo.

**Commits grouped into one batch go far further than commits sent at once.** Landed in NRT:

| How the commits are sent                   | Time                         | Commits a second       |
| ------------------------------------------ | ---------------------------- | ---------------------- |
| one a request, one after another           | 26 ms in the Worker          | about 25               |
| 8 or 32 connections at once, one a request | 63 to 77 ms from the machine | about 100, and no more |
| 32 in one batch                            | 30 ms in the Worker          | about 640              |
| 128 in one batch                           | 41 ms in the Worker          | about 1,900            |

**Writing through a batch of 64 KiB segments is slow for bulk**: 1 MiB in 16 segments took about
240 ms from Tokyo, some 4 MiB a second on one connection.

**What the free plan allows**, read the same day. Sources:
https://developers.cloudflare.com/workers/platform/limits/,
https://developers.cloudflare.com/d1/platform/limits/ and
https://developers.cloudflare.com/durable-objects/platform/pricing/

- Workers: 100,000 requests a day, 10 ms of CPU a request, 50 subrequests, 100 Workers an account,
  5 cron triggers.
- D1: 10 databases an account, 500 MB each and 5 GB in all, 50 queries an invocation; 5 million
  rows read and 100,000 rows written a day. An `INSERT`, `UPDATE` or `DELETE` counts each row it
  touches, and an index adds a row written when a write includes its column. On Workers Paid, 50
  million rows written a month are included, then $1.00 a million, and 5 GB stored, then $0.75 a
  GB-month. Whether space a deletion frees still counts as stored is not said. Source:
  https://developers.cloudflare.com/d1/platform/pricing/
- Durable Objects: the SQLite-backed kind alone, with 100,000 requests, 5 million rows read and
  100,000 rows written a day, and 5 GB stored.
- R2: 10 GB-months stored, 1 million Class A and 10 million Class B requests a month free; then
  $0.015 a GB-month, $4.50 a million Class A and $0.36 a million Class B. `PutObject` and
  `ListObjects` are Class A, `GetObject` and `HeadObject` Class B, `DeleteObject` free. Source:
  https://developers.cloudflare.com/r2/pricing/
- The Worker Loader is on the paid plan alone, and Workers for Platforms is a plan of its own, at
  $25 a month: https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/platform/pricing/
