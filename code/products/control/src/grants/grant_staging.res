module Context = Grant_context

let sweepBound = 20.

let quiet = async (work, ~what) =>
  switch await work() {
  | () => ()
  | exception JsExn(_) => Console.error(`grant staging, ${what} did not finish`)
  }

// Bytes go before the row, so what fails leaves a row the sweep finds again.
let removed = async (t: Context.t, rows: array<Grant_store.stagedRow>) => {
  for i in 0 to rows->Array.length - 1 {
    let {grant, digest} = rows->Array.getUnsafe(i)
    await t.artifacts.delete(Context.stagingKey(grant, digest))
    await Grant_store.unstage(t.store, grant, digest)
  }
}

let sweep = t =>
  quiet(
    async () => await removed(t, await Grant_store.expired(t.store, sweepBound)),
    ~what="a sweep",
  )

let discard = (t, grant, digest) =>
  quiet(async () => await removed(t, [{grant, digest}]), ~what="a recorded deploy's staging")

let revoked = (t, grant) =>
  quiet(async () => await removed(t, await Grant_store.stagedBy(t.store, grant)), ~what="a revoke")

let retired = (t, app) =>
  quiet(async () => await removed(t, await Grant_store.stagedFor(t.store, app)), ~what="a retire")

// What a driver fetches, read only with the artifact's own token while its grant stands.
let served = async (store: Grant_store.t, artifacts: Artifacts.t, ~grant, ~digest, ~token) =>
  switch await Grant_store.fetchable(store, grant, digest) {
  | Some(row)
    if row.revoked == 0 &&
    row.expires > store.now() &&
    row.lapses > store.now() &&
    Access.equal(Web.utf8(row.token), Web.utf8(token)) =>
    await artifacts.served(Context.stagingKey(grant, digest))
  | Some(_) | None => None
  }
