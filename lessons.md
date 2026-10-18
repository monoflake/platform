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

**A tunnel keeps four connections out, and a request finds the nearest.** `cloudflared` makes
"four outbound-only connections" to "four different servers spread across at least two distinct
data centers"; a request "arriving at Cloudflare is forwarded to the geographically closest
replica", up to 25 replicas a tunnel. Its protocol is QUIC by default, falling back to HTTP/2 where
UDP cannot be had. How much an idle tunnel sends to keep itself alive is not published, and is to
be measured. Asked of relays, RFC vr5lw, read 2026-10-18. Sources:
https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/tunnel-availability/
and
https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/cloudflared-parameters/run-parameters/

**Another account's Worker can serve a name of ours as a custom hostname.** Cloudflare for SaaS is
offered on the Free, Pro and Business plans with 100 custom hostnames included, then $0.10 a hostname
to 50,000. The zone serving them must be on Cloudflare with the feature turned on; a hostname points
at it by a CNAME, its certificate is validated by TXT, delegated DCV or HTTP, before the cutover if
asked; and a `*/*` route on that zone sends every custom hostname's traffic to a Worker, its fallback
origin an originless proxied record. Wildcard custom hostnames are offered on Enterprise alone, "No" on Free, Pro and Business. Asked of a platform name served by a user's account, RFC
vr5lw, read 2026-10-18. Sources:
https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/plans/,
https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/getting-started/
and
https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/start/advanced-settings/worker-as-origin/

**A custom hostname's certificate is its own, for that name alone.** Cloudflare issues SSL for SaaS
certificates through Let's Encrypt, Google Trust Services or SSL.com, and the API takes a
`certificate_authority` to choose among them, empty for the default, which checks CAA first; which
values it takes is not on the reference page. No limit on a custom hostname's depth is written; a
post of December 2025 reports a fourth-level name given a certificate in under a minute on Cloudflare
for SaaS without Advanced Certificate Manager. That the same holds for a name of another account's
zone pointing at it DNS only is to be tried. A certificate issued through Let's Encrypt counts toward
that CA's limit for the name's registered domain, whoever asks. Asked of a platform name served by a
user's account, RFC vr5lw, read 2026-10-18. Sources:
https://developers.cloudflare.com/ssl/reference/certificate-authorities/,
https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/security/certificate-management/issue-and-validate/issue-certificates/
and https://hajekj.net/2025/12/22/protecting-4th-level-domains-with-cloudflare-for-free/

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
- R2's S3 API copies an object without it passing through the caller, `CopyObject`, with its
  `x-amz-copy-source-if-*` conditions, and builds one from ranges of others, `UploadPartCopy`,
  without them; it has no rename, so a move is a copy and a deletion. Source:
  https://developers.cloudflare.com/r2/api/s3/api/. Amazon S3's `RenameObject` exists only for
  directory buckets in S3 Express One Zone:
  https://docs.aws.amazon.com/AmazonS3/latest/API/API_RenameObject.html
- The Worker Loader is on the paid plan alone, and Workers for Platforms is a plan of its own, at
  $25 a month: https://developers.cloudflare.com/cloudflare-for-platforms/workers-for-platforms/platform/pricing/

## Let's Encrypt, read 2026-10-18

**A registered domain gets 50 certificates a week, and the Public Suffix List says what one is.**
"Up to 50 certificates can be issued per registered domain ... every 7 days", across all accounts;
"We use the Public Suffix List to identify registered domains." "Up to 300 new orders can be created
by a single account every 3 hours." A renewal coordinated by ARI is "exempt from all rate limits";
one for the exact same names is exempt from the order and registered-domain limits. A certificate for the exact same set of names is issued at most 5 times
every 7 days, across all accounts. Asked of names
the platform gives machines, RFC vr5lw. Source: https://letsencrypt.org/docs/rate-limits/

**The Public Suffix List takes a private domain by a pull request, and turns away one made to escape
a rate limit.** A suffix is added under the private domains, validated by a `_psl` TXT record whose
value is the pull request's address, by a domain with more than two years of registration left. It
is likely declined when its sole purpose is to get around a third party's rate limits -- Let's
Encrypt has a form of its own for those -- or when the project serves fewer than thousands of users;
review has no promised time, and clients take a change up on their own schedules. Asked of names the
platform gives organizations, RFC vr5lw, read 2026-10-18. Source:
https://github.com/publicsuffix/list/wiki/Guidelines

## Google's public CA, read 2026-10-18

**Google's public CA takes 100 orders an hour a project, and names no limit a domain.** It is
reached by ACME with external account binding, each ACME account bound to a Google Cloud project,
whose accounts share the project's quotas: 100 `newOrder` an hour, 300 `newAuthz` an hour, 100
`newAccount` an hour, and adjustments may be asked. Wildcards are validated by the DNS challenge
alone. No limit a domain is listed for it, and its price and certificates' lifetime are not on the
page. Asked of names the platform gives machines, RFC vr5lw. Sources:
https://docs.cloud.google.com/certificate-manager/docs/public-ca and
https://docs.cloud.google.com/certificate-manager/docs/quotas

## Workers VPC, read 2026-10-18

**A Worker reaches what stands behind a Cloudflare Tunnel by a binding, in beta and free while it
is.** A VPC Service binds a Worker to one host and port behind a tunnel, HTTP and TCP, TCP databases
through Hyperdrive; a VPC Network binds it to a whole tunnel, a Cloudflare Mesh network or a WAN
on-ramp, HTTP by `fetch()` and raw TCP by `connect()`. The targets are described as not reachable
from the public Internet. "Available on Free and Paid plans"; "While in beta, Workers VPC is
available for free to all Workers plans"; "Features and APIs may change before general
availability". Its price after the beta and its limits are not on the page. Asked of a Worker's way
into a private network, RFC vr5lw. Sources: https://developers.cloudflare.com/workers-vpc/ and
https://developers.cloudflare.com/changelog/product/workers-vpc/

## Tailscale, read 2026-10-18

**The free Personal plan is for non-commercial use, and counts a tagged device among 50.** Up to 6
users, user devices unlimited, 50 tagged resources included and $1 a month each past them, 1,000
ephemeral minutes a month, 3 ACL groups; "only suitable for non-commercial use of Tailscale". The
FAQ still says 3 users and 100 devices; the pricing page is the newer. Asked of a tailnet as a
host, RFC vr5lw. Sources: https://tailscale.com/pricing/ and https://tailscale.com/kb/1251/pricing-faq

**A device joined by an OAuth client's key is tagged, and the client names its tags.** A client
given the `auth_keys` scope must be given one or more tags, and every key it makes carries tags;
"Devices registered with OAuth client credentials are tag-owned". `devices:core` reads, authorizes
and removes devices and manages their tags. Source: https://tailscale.com/kb/1215/oauth-clients

**The policy file is one document, replaced whole, guarded by its ETag.** A read returns an `ETag`;
a write replaces the whole file and, given `If-Match`, fails when the file changed since. Read from
a copy of the API reference, not Tailscale's own page, so to be confirmed. Source:
https://github.com/Lewinz/tailscale/blob/main/api.md

## Building code, read 2026-10-18

**`workerd` is no hardened sandbox.** "`workerd` on its own does not contain suitable
defense-in-depth against the possibility of implementation bugs"; "When using `workerd` to run
possibly-malicious code, you must run it inside an appropriate secure sandbox, such as a virtual
machine." Apache-2.0. Asked of V8 on a machine, RFC vr5lw. Source:
https://github.com/cloudflare/workerd

**A GitHub Actions workflow is started by the API, with no push.** `workflow_dispatch` takes a ref
and at most 10 inputs, its workflow file on the default branch; `repository_dispatch` takes an event
type and a payload, and is reported to start only the default branch's workflow, to be confirmed.
Asked of building for a target, RFC vr5lw. Sources:
https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow and
https://github.community/t/how-to-trigger-repository-dispatch-event-for-non-default-branch/14470

**GitHub Actions is free on standard runners for a public repository, and counts minutes for a
private one against its owner.** GitHub Free includes 2,000 minutes a month, Pro and Team 3,000;
past them a spending limit of 0 by default stops runs. "Minutes usage is charged to the repository
owner, not the person who triggered the workflow runs." Source:
https://docs.github.com/en/actions/concepts/billing-and-usage

**GitHub Actions keeps an artifact 90 days unless set otherwise**: 1 to 90 days for a public
repository, 1 to 400 for a private or internal one, a change reaching only what is made after it.
Source:
https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization

**Cloudflare's Workers Builds builds a connected repository, and its deploy command may be
changed.** Free: 3,000 build minutes a month, 1 build at a time; paid: 6,000, then $0.005 a minute,
6 at a time; 20 minutes a build, 2 vCPU, 8 GB of memory, 20 GB of disk. "Your deploy command will
default to `npx wrangler deploy` but you may customize this command"; `npx wrangler versions upload`
makes a version and deploys nothing. A build is started by `POST
/accounts/{account_id}/builds/triggers/{trigger_uuid}/builds`, a branch optional, with a user-scoped
token holding Workers CI Write -- an account-scoped one is refused -- or by a deploy hook, 10 a
minute a Worker and 100 an account. Sources:
https://developers.cloudflare.com/workers/ci-cd/builds/limits-and-pricing/,
https://developers.cloudflare.com/workers/ci-cd/builds/configuration/ and
https://developers.cloudflare.com/workers/ci-cd/builds/api-reference

**A Worker can be rolled back to any of its last 100 versions**, raised from 10 in September 2025,
unless a binding it names is gone or a Durable Object class changed between them. Source:
https://developers.cloudflare.com/workers/versions-and-deployments/rollbacks/

**A Worker is at most 3 MB on the free plan and 10 MB on the paid, and its global scope runs within
a second.** The size is counted compressed; the startup limit was raised from 400 ms to 1 second in
October 2025, on both plans. Some older pages show 64 MiB and 400 ms, and are stale. Asked of what
bounds code on a target, RFC vr5lw. Sources: https://developers.cloudflare.com/workers/platform/limits
and https://developers.cloudflare.com/changelog/2025-10-10-increased-startup-time/
