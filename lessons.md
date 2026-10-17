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

**A Worker's limits** on Workers Paid, asked by B13. Source:
https://developers.cloudflare.com/workers/platform/limits/

- 128 MB of memory.
- CPU time 30 seconds by default, up to 5 minutes set; waiting on the network is not counted.
- 10,000 subrequests a request.
- A request's body is limited by the account's plan: 100 MB on Free and Pro, 200 MB on Business,
  up to 5 GB on Enterprise.
