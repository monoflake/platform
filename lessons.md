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

**A Worker's WebCrypto signs and verifies Ed25519**, by the name `Ed25519` under the Secure Curves
API, or the older `NODE-ED25519`, which takes no raw private key. Asked of the signed record of RFC
b8f35. Source: https://developers.cloudflare.com/workers/runtime-apis/web-crypto/

## SQLite at size, read 2026-10-18

**SQLite's file is bounded by its pages, and the file system comes first.** "The maximum size of a
database file is 4294967294 pages": about 17.5 TB at the default 4 KiB page, about 281 TB at 64 KiB,
the latter "untested"; the default page count has been that maximum since 3.45.0. A growth past it
returns `SQLITE_FULL`, as does a file system's own limit, "usually much less". A table holds 2^64
rows in theory, and at 281 TB "no more than approximately 2e+13". Asked of what bounds a footing,
RFC b8f35. Source: https://www.sqlite.org/limits.html

**SQLite advises a client/server database once content nears a terabyte.** "For device-local storage
with low writer concurrency and less than a terabyte of content, SQLite is almost always a better
solution"; "when the size of the content looks like it might creep into the terabyte range, it
would be good to consider a centralized client/server database"; one writer at a time. Source:
https://www.sqlite.org/whentouse.html

**SQLite has been run at billions of rows**: 10 billion rows in 447 GB fully cached in 1 TB of
memory at 4 million queries a second, and 30 billion in 1.3 TB, past memory, on a modified SQLite;
and about 8.9 billion in 426 GB on an SSD, inserted in 6 hours and indexed in 8. Sources:
https://use.expensify.com/blog/scaling-sqlite-to-4m-qps-on-a-single-server and
https://sqlite-users.sqlite.narkive.com/KjYJgmcU/sqlite-boosting-insert-and-indexing-performance-for-10-billion-rows

**Keys in random order insert an order of magnitude slower once a table outgrows its cache.** On an
i7-9700K with NVMe, 5 million keys went in at 3,030,000 rows a second in order and 161,000
shuffled; 10 million random keys at 306,000 with a cache of 2,000 pages and 988,000 with
2,000,000. Random inserts grow faster than linearly while the table is larger than the cache, then
linearly once nearly every access misses. Asked of the extent, whose keys are hashes. Source:
https://voidstar.tech/sqlite_insert_speed/

**D1 names no page size.** Its compatible PRAGMA statements include `table_list`, `table_info`,
`index_list`, `quick_check`, `foreign_keys` and `optimize`, among others, and none of `page_size`,
`page_count`, `cache_size` or `mmap_size`. Source: https://developers.cloudflare.com/d1/sql-api/sql-statements/

## Media types and extensions, read 2026-10-19

**mime-db groups extensions by the type they are served as, never by spelling.** In 1.54.0, 2522
types are listed, 1015 of them with extensions, 1239 extensions in all, and 48 extensions listed under
more than one type: `js` under `application/javascript` and `text/javascript`, `mp4` under
`application/mp4` and `video/mp4`. A type lists several: `image/jpeg` is `jpg`, `jpeg`, `jpe`, in that
order; `text/yaml` is `yaml`, `yml`; `text/markdown` is `md`, `markdown`; `text/plain` is `txt`,
`text`, `conf`, `def`, `list`, `log`, `in`, `ini`. `ts` is `video/mp2t` alone. So a type never leads
back to one extension, and the first listed is not always the long spelling. Asked by checklist A8.
Source: https://cdn.jsdelivr.net/npm/mime-db@1.54.0/db.json

**WHATWG's sniffing obeys the type given once no-sniff is set**, and counts HTML, XML and PDF among
the types a page could run, apart from its image, audio, video, font and archive patterns. Go's
`DetectContentType` follows it over the first 512 bytes and answers `application/octet-stream` when
it cannot tell. Asked by A8. Sources: https://mimesniff.spec.whatwg.org/ and
https://pkg.go.dev/net/http#DetectContentType

**Three-letter extensions are mostly four-letter names cut short.** CP/M and the FAT file system of
early MS-DOS and Windows allowed eight characters and an extension of three, and early Windows
programs wrote three; classic Mac OS allowed longer. Pairs named: `jpg` `jpeg`, `tif` `tiff`, `pct`
`pict`, `mpg` `mpeg`, `mid` `midi`, `aif` `aiff`, `wav` `wave`, `htm` `html`. The short ones
outlived the limit, Windows being the most used. Asked by A8. Source:
https://fileinfo.com/help/different_extensions

**MDN names the type of each common extension**, IANA's where one is registered: `md`
`text/markdown`, `js` and `mjs` `text/javascript` by RFC 9239, `flac` `audio/flac` where mime-db has
only `audio/x-flac`, `wav` `audio/wav` with `audio/wave` preferred by its container page, `ico`
`image/vnd.microsoft.icon`, `xml` `application/xml` by RFC 7303. `jxl`, `heic`, `tiff` and `mov`
are not shown by every browser: TIFF by Safari alone, QuickTime by Safari. Asked by A8. Sources:
https://developer.mozilla.org/en-US/docs/Web/HTTP/Guides/MIME_types/Common_types,
https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Image_types and
https://developer.mozilla.org/en-US/docs/Web/Media/Guides/Formats/Containers

**`Content-Security-Policy: sandbox` with no token makes a page show and do nothing.** Its origin is
opaque, so `document.cookie` and `localStorage` are out of reach and every same-origin check
fails; scripts do not run; a form is shown but never sent; popups and top-level navigation are
refused. It works only as a response header, never in `<meta>`, and has been in every browser since
November 2016. A response's policy populates the policy container of the document or worker made
from it; a page's own policy governs the requests it makes. Asked by A8. Sources:
https://developer.mozilla.org/en-US/docs/Web/HTTP/Reference/Headers/Content-Security-Policy/sandbox,
https://html.spec.whatwg.org/multipage/browsers.html#sandboxing and https://www.w3.org/TR/CSP3/

**Chrome shows a PDF blank when its response carries `sandbox`.** Jira, which sends the header on
attachments from 8.16, excludes `application/pdf` to make them load. Asked by A8. Sources:
https://support.atlassian.com/jira/kb/pdf-attachments-fail-to-load-in-chrome-on-jira-data-center/
and https://answers.sap.com/questions/13392550/chrome-blocking-pdf-content-accessed-via-media-url.html

## COSE, read 2026-10-19

**COSE names Ed25519 by -19, and the polymorphic `EdDSA`, -8, is deprecated.** RFC 9864, October
2025, registers fully specified algorithms: `Ed25519` -19 and `Ed448` -53, both recommended, and
marks `EdDSA` -8 "Deprecated", since an identifier covering two curves cannot be negotiated; WebAuthn
had worked around it by reading -8 as Ed25519 alone. Asked by checklist A11. Source:
https://www.rfc-editor.org/rfc/rfc9864.html

**D1 names no PRAGMA that makes a connection read only, and no authorizer.** Its compatible PRAGMA
statements are `table_list`, `table_info`, `table_xinfo`, `index_list`, `index_info`,
`index_xinfo`, `quick_check`, `foreign_key_check`, `foreign_key_list`, `case_sensitive_like`,
`ignore_check_constraints`, `legacy_alter_table`, `recursive_triggers`,
`reverse_unordered_selects`, `foreign_keys`, `defer_foreign_keys` and `optimize`; `query_only` is
not among them, and `EXPLAIN` is not named. Asked by checklist B21. Source:
https://developers.cloudflare.com/d1/sql-api/sql-statements/

**CWT keeps claim keys below -65536 for private use**, and has registered `scope` as 9, from OAuth,
and `sub` as 2, a text string; -256 to 255 take Standards Action, -65536 to -257 and 256 to 65535
Specification Required, and above 65535 Expert Review. Asked by checklist A11. Source:
https://www.iana.org/assignments/cwt/cwt.xhtml

## SLIP-39, read 2026-10-19

**SLIP-39 writes a Shamir share as words.** Its list holds exactly 1024 words, each with a unique
four-letter prefix, so a word carries 10 bits; a share of a 128-bit secret is 20 words and of a
256-bit one 33. The last three words are a Reed-Solomon checksum that detects any error in up to
three words, and misses a larger one with less than a one-in-a-billion chance; the spec advises
against correcting automatically. Thresholds are two-level, up to 16 groups of up to 16 members. The
master secret may be encrypted under a passphrase of printable ASCII, empty if none is given, and
nothing tells a wrong passphrase from a right one. Asked by checklist B12. Source:
https://github.com/satoshilabs/slips/blob/master/slip-0039.md

## Names in a domain, read 2026-10-19

**No publicly trusted CA certifies a host's name with an underscore.** CA/Browser Forum Ballot SC12,
"Sunset of Underscores in dNSNames", passed in November 2018, ended the exception that had let
them through, since RFC 5280 never allowed them; certificates with one were cut to 30 days and
phased out in 2019. Asked by checklist B3. Sources:
https://lists.cabforum.org/pipermail/servercert-wg/2018-November/000362.html and
https://ssl.com/?p=26132

**A site's reserved usernames are listed by shouldbee/reserved-usernames**, 602 names under MIT,
last changed 2021-07-14: paths a site keeps from its users, as `admin`, `api`, `login`, `settings`,
`status`, `www`, `mail` and `ns1`, with a few misspellings and Spanish and Portuguese words among
them. 577 fit a name of 3 or more lowercase letters, digits and hyphens. Asked by checklist B3.
Source: https://github.com/shouldbee/reserved-usernames, kept in `vendor/reserved-usernames/`

**RFC 2142 names the mailboxes a domain keeps**: `info`, `marketing`, `sales` and `support` for a
business; `abuse`, `noc` and `security` for network operations; `postmaster`, `hostmaster`,
`usenet`, `news`, `webmaster`, `www`, `uucp` and `ftp` for its services. Asked by B3. Source:
https://www.rfc-editor.org/rfc/rfc2142.html

## Claiming a domain, read 2026-10-19

**`/.well-known/` is RFC 8615's prefix for metadata of a whole origin**, in HTTP, HTTPS, WS and WSS
URIs, kept apart from the origin's own paths. "Applications that wish to mint new well-known URIs
MUST register them", by Specification Required; a suffix holds no `/`. ACME's HTTP challenge fetches
`/.well-known/acme-challenge/{token}`. Asked of a domain's proof, RFC vr5lw. Source:
https://www.rfc-editor.org/rfc/rfc8615.html

**Cloudflare for SaaS proves a custom hostname by a TXT record or an HTTP token**, the latter at
`/.well-known/cf-custom-hostname-challenge/{id}`, answered 200 with a body it gives, fetched with
the User-Agent "Cloudflare Custom Hostname Verification"; for a customer that cannot change its DNS
or take downtime. Pre-validation is not offered for O2O hostnames, which validate in real time. Asked
by C26. Source:
https://developers.cloudflare.com/cloudflare-for-platforms/cloudflare-for-saas/domain-support/hostname-validation/pre-validation/

**RDAP is where a gTLD's registration is read since 2025-01-28**, ICANN's date for WHOIS's sunset.
An answer is JSON whose `events` each hold an `eventAction` and an `eventDate` in RFC 3339; the
action `expiration` is registered, and may be dated in the future. `example.com` answered,
2026-10-19, registration 1995-08-14 and expiration 2027-08-13. IANA's bootstrap of 2026-09-30 names
an RDAP server for 1203 TLDs, `com`, `net`, `org`, `dev`, `app`, `fyi`, `ai` and `uk` among them,
and none for `io`, `cn`, `de`, `jp`, `us` or `co`. Asked of a domain's proof, RFC vr5lw. Sources:
https://www.icann.org/en/announcements/details/icann-update-launching-rdap-sunsetting-whois-27-01-2025-en,
https://www.rfc-editor.org/rfc/rfc9083.html and https://data.iana.org/rdap/dns.json

## A machine's system, read 2026-10-19

**NixOS 26.05 "Yarara" is the stable release, out 2026-05-30**, with fixes and security updates
until 2026-12-31; 25.11 lost its security updates after 2026-06-30. Its stage 1 runs systemd by
default. So a machine installed now crosses a release within months. Asked of a machine's system, RFC
vr5lw. Sources: https://nixos.org/blog/announcements/2026/nixos-2605/ and
https://www.phoronix.com/news/NixOS-26.05-Released

**containerd is spoken from Rust by `containerd-client`**, gRPC bindings generated from
containerd's protobuf definitions, in containerd's own `rust-extensions` repository, reached at
`/run/containerd/containerd.sock`; `containerd-shim-protos` beside it holds the shim v2 protocol.
docs.rs failed to build 0.8.0's documentation and shows 0.6.0's. Asked of a machine's driver, RFC
vr5lw. Source: https://docs.rs/containerd-client

**containerd runs crun through runc's shim**: `runtime_type` `io.containerd.runc.v2`, with
`options.BinaryName` naming crun's binary. The shim calls its runtime as runc is called, so only a
runtime compatible with it runs so; Kata brings a shim of its own. Whether youki does is not found.
Asked by checklist C32. Sources: https://blog.nuvotex.de/crun/ and
https://git.causa-arcana.com/kotovalexarian-likes-github/moby--moby/commit/6de52a29a8e8fbe9639178a25f716bfe4532ff11

**A container outlives containerd's restart**: its shim is its parent once runc has made it, so it
runs on while containerd is down, though nothing is created or deleted until containerd returns.
Asked by C32. Sources: https://github.com/moby/moby/discussions/46449 and
https://forums.docker.com/t/the-parent-process-issue/142026

**Docker's live restore keeps containers running while its daemon is down, across patch releases
alone**: set `"live-restore": true` in `/etc/docker/daemon.json`; it is "only supported" across
`YY.MM.x`, not a `YY.MM` upgrade, and restores only while the bridge's addresses and the graph driver
are unchanged; a long outage can fill a container's log buffer and block its logging; standalone
containers alone, not Swarm's. Asked by checklist C32. Source:
https://docs.docker.com/engine/daemon/live-restore/

**Btrfs has two quotas**: qgroups, which walk back-references on writes and commits and slow as
snapshots grow, and simple quotas from Linux 6.7, `btrfs quota enable --simple`, which charge each
extent for good to the subvolume that made it and cost about what no quota does, but cannot tell
shared from exclusive use. Asked by B22. Sources: https://lwn.net/Articles/944371,
https://blogs.oracle.com/linux/btrfs-qgroup-quota-vs-simple-quota and
https://btrfs.readthedocs.io/en/latest/btrfs-quota.html

## Contracts and their encodings, read 2026-10-19

**ATD is a language of types for data crossing languages**, its core neutral of format: "Types are
mapped to each programming language or data format using language-specific conventions", and it
takes annotations of any name. Its README lists atdcpp, atdd, atdj, atdgen for OCaml, "legacy", and
Melange, atdml for OCaml "coming soon", atdpy, atds and atdts, and no Rust; `atdcat -jsonschema`
exports JSON Schema. Its core reference is 651 lines; its tests are each backend's own, 82 files for
atdgen, 21 for atdts, 13 for atdpy, and no conformance suite. It is under BSD's three clauses.
Melange is served by atdgen's `-mel` and `melange-atdgen-codec-runtime`, 3.0.1 of 2025-03-17, work
Ahrefs funded. Asked by RFC fhg6w. Sources: https://github.com/ahrefs/atd,
https://atd.readthedocs.io/en/latest/atd-language.html,
https://ocaml.org/p/melange-atdgen-codec-runtime and
https://tech.ahrefs.com/getting-started-with-atd-and-melange-1f3a14004081

**Melange is OCaml's compiler for applications whose other half is JavaScript; js_of_ocaml for
reusing OCaml that exists.** OCaml.org gives Melange idiomatic output, deep integration with npm and
its tools, and "Excellent TypeScript interoperability", a module a file; js_of_ocaml compatibility
with most libraries and the standard library, OCaml 5's effects, limited support for domains, and
32-bit integers. Asked by fhg6w. Source: https://ocaml.org/tools/javascript-target

**CBOR is RFC 8949, 3674 lines of text, with its tests in it.** Its Appendix A has 82 encoded items,
kept as JSON in `cbor/test-vectors`, 65 marked to re-encode byte for byte and 59 decodable as JSON;
the repository states no license, and the items are the RFC's own. Its Appendix F lists about 90
byte sequences that are not well formed, by kind: input ending in a head, strings and containers
short of their items, reserved values, chunks of the wrong type, unclosed indefinite lengths. Its
4.2 defines deterministic encoding. Asked by fhg6w. Sources:
https://www.rfc-editor.org/rfc/rfc8949.txt and https://github.com/cbor/test-vectors

**COSE is RFC 9052, about 3600 lines, and CWT RFC 8392, 25 pages**; `cose-wg/Examples`, under the
Unlicense, holds 306 JSON cases, `sign1-tests`, `eddsa-examples` and `CWT` among them, written
before RFC 9864, so their EdDSA is -8. Asked by fhg6w. Sources:
https://www.rfc-editor.org/rfc/rfc9052.txt, https://www.rfc-editor.org/rfc/rfc8392.txt and
https://github.com/cose-wg/Examples

**OCaml today is opam 2.6.1, of 2026-10-07, OCaml 5.5.1, of 2026-09-04, and dune 3.24.2.** ocaml.org
installs it by opam, and warns that an opam from a system's package manager may be too old for the
newest compiler. A switch is "an isolated environment for the OCaml compiler and any packages you
install". Dune's own package management takes dependencies from `dune-project` into a lock file,
solved from nothing, with a relocatable compiler cached apart from the project; opam is kept beside
it. Asked by RFC fhg6w. Sources: https://ocaml.org/install,
https://dune.readthedocs.io/en/stable/explanation/package-management.html and
https://github.com/ocaml/opam/releases

**OCaml's servers, read 2026-10-19**: Dream 1.0.0, of 2026-10-07, after years of alphas and a new team
of maintainers from January 2026, MIT, on Lwt -- its handlers functions, its middleware composed by
`@@`, with sessions, CSRF, WebSockets, GraphQL, templates, TLS and HTTP/2 -- and a port to Eio under
way; cohttp-eio 6.3.0, a multicore HTTP/1.1 server in direct style on Eio, with no router or
middleware; httpun-eio 0.2.0, lower still; Vif 0.0.1~beta6 on Miou, "we do not recommend using this
project in production"; Piaf, a client. A 2026 account of OCaml web work in production uses Eio and
cohttp. Asked by fhg6w. Sources: https://github.com/camlworks/dream,
https://discuss.ocaml.org/t/the-new-owners-maintainers-of-dream/17712, https://ocaml.org/p/cohttp-eio,
https://github.com/robur-coop/vif and https://www.m3tech.blog/entry/2026/05/26/150000

**OCaml's libraries beside its own**: Base, "a complete and portable alternative" offering no I/O,
shadows the standard modules, and some of its functions differ, `List.map` tail-recursive in Base
and not in Stdlib; Core builds on it; Containers extends Stdlib rather than replacing it. Asked by
fhg6w. Sources: https://ocaml.org/p/base/latest and
https://discuss.ocaml.org/t/stdlib-vs-base-in-2025-beginner/16626

**Dune's package management is "not final yet and details are still subject to change"**, its
tutorial says. 3.24.0, of 2026-06-21, made the relocatable compiler its default, built once and
cached apart from a project, and locks developer tools, `dune fmt` using a locked ocamlformat;
3.25.0_alpha0 came on 2026-10-02. It installs the compiler and third-party packages by one tool from
opam's repositories, reading `.opam` files still; it installs no system package, sandboxes no build
as opam does by Bubblewrap, needs packages free of absolute paths, patching others in an overlay
repository, and solves from nothing. Open in its tracker: Windows, cross-compilation. mise's
registry holds opam, `github:ocaml/opam`, and no OCaml compiler or dune. Asked by RFC fhg6w. Sources:
https://dune.readthedocs.io/en/stable/tutorials/dune-package-management/index.html,
https://dune.readthedocs.io/en/stable/explanation/package-management.html and
https://github.com/ocaml/dune/releases

**Rust's CBOR crates, read 2026-10-19**: minicbor 2.3.1, of 2026-10-18, Blue Oak 1.0.0, no_std, with
`Encode` and `Decode` it derives and serde in `minicbor-serde`; ciborium 0.2.2, of 2024-01-24,
Apache-2.0, serde's, keeping a map's pairs in the order they came. Neither's documentation speaks of
deterministic encoding. OCaml's: cborl 0.1.0, AGPL, without half floats or indefinite strings; cbort,
ISC, on Zarith and bytesrw; cbor 0.4, RFC 7049's. Asked by RFC fhg6w. Sources:
https://docs.rs/minicbor/latest/minicbor/, https://github.com/enarx/ciborium, https://ocaml.org/p/cborl
and https://tangled.org/gazagnaire.org/ocaml-cbort

## The platform's languages after OCaml, read 2026-10-19

**ReScript is 12.3.1, of 2026-08-24**; 12.0.0, of 2025-11-25, brought a rewritten build system,
Rewatch, tracking dependencies across a monorepo's packages, with the old one kept as
`rescript-legacy`, and `@rescript/core` folded into the compiler as its standard library. 13 is
aimed at the fourth quarter of 2026, "release contents and timing may change": Rewatch alone, the
Ninja builder removed, source maps, ES modules by default, node 22 at least, and `.d.ts` files
generated by the compiler for the JavaScript it writes, so TypeScript reads a ReScript library with
no step beside it. Its `int` is 32 bits. Asked by RFC fhg6w. Sources:
https://rescript-lang.org/blog/release-12-0-0, https://en.wikipedia.org/wiki/ReScript,
https://rescript-lang.org/community/roadmap/ and
https://v11.rescript-lang.org/docs/manual/v11.0.0/primitive-types

**ReScript's own packages are few**: `rescript` counted between about 11,700 and 40,900 downloads a
week by sources that disagree, `@rescript/react` 5,776; it reaches npm's libraries by bindings. It
has no integration with Svelte: its team says a `.svelte` file imports the compiled JavaScript
instead, and a preprocessor for `<script lang="res">` exists only as a forum's sketch. Asked by
fhg6w. Sources: https://snyk.io/advisor/npm-package/rescript, https://depscope.dev/pkg/npm/rescript,
https://www.npmjs.com/package/@rescript/react,
https://rescript-lang.org/blog/what-can-i-do-with-rescript and
https://forum.rescript-lang.org/t/use-rescript-with-svelte/1762

**Rust on a Worker is `workers-rs`, the `worker` crate, 0.8.6**, built for
`wasm32-unknown-unknown`, with bindings for D1 and Durable Objects among others, and no tokio or
async-std. Asked by fhg6w. Sources: https://docs.rs/crate/worker/0.8.6 and
https://cdn.jsdelivr.net/gh/cloudflare/workers-rs@main/README.md

**ATD's tools are OCaml programs installed by opam**: `atdts` is not on npm, 404 on 2026-10-19, and
none of `atdts`, `atdgen` or `atdcat` is on this machine. atdgen's backend for BuckleScript,
ReScript's former name, is served by `atdgen-codec-runtime`, and no ReScript backend is named. Asked
by fhg6w. Sources: https://registry.npmjs.org/atdts,
https://opam-4.ocaml.org/packages/atdgen-codec-runtime/atdgen-codec-runtime.2.3.3 and
https://github.com/ahrefs/atd

**ReScript meets Workers and Hono by bindings the platform writes**: none named `rescript-hono` is
found, and `workers-res`, "Cloudflare Workers bindings for ReScript", is 0.0.3, a work in progress
with KV alone done. Hono's app is a fetch handler, so a binding wraps one function. Sury, formerly
`rescript-schema`, writes and reads JSON Schema, `S.toJSONSchema` and `S.fromJSONSchema`, its 11
in alpha. Asked by RFC fhg6w. Sources: https://npmjs.com/package/workers-res,
https://www.mintlify.com/honojs/hono/deployment/cloudflare-workers,
https://unpkg.com/sury@11.0.0-alpha.9/README.md and https://bestofjs.org/projects/sury

**ReScript's values are JavaScript's where they can be**: a record compiles to a plain object, an
array to an array, a string to a string, so they cross to TypeScript unconverted; a variant with a
payload compiles to an object tagged `TAG`, `{ TAG: "A"; _0: number }` in genType's TypeScript, and
genType exports ReScript's values and types to TypeScript and imports TypeScript's into ReScript.
Asked by RFC fhg6w. Sources: https://rescript-lang.org/docs/manual/latest/shared-data-types and
https://www.rescript-lang.org/docs/manual/typescript-integration
