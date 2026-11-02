module C = Envelope.Contracts
module Context = Grant_context

type t = {at: float, grant: string, digest: string, candidate: string, ingress: string, size: float}
let duration = 300000.

// Every driver call under a lease ends before the lease does.
let deadline = 240000

// deployment_grants declares no reason named unavailable, so this global one carries that failure.
let unavailable = Serve.Calls.Refused({
  reason: "overloaded",
  message: Some("an earlier deploy's outcome is not known yet, try again"),
})

// The driver may have acted on a call answered with one of these.
let ambiguous = reason => ["unreachable", "bad_answer", "fault"]->Array.includes(reason)

let encode = (lease, ~nonce="") =>
  JSON.stringify(
    JSON.Object(
      dict{
        "nonce": String(nonce),
        "at": Number(lease.at),
        "grant": String(lease.grant),
        "digest": String(lease.digest),
        "candidate": String(lease.candidate),
        "ingress": String(lease.ingress),
        "size": Number(lease.size),
      },
    ),
  )
let decode = text =>
  switch JSON.parseOrThrow(text) {
  | json =>
    let field = name => Grant_archive.field(json, name)
    switch (
      field("at")->Option.flatMap(JSON.Decode.float),
      Grant_archive.text(json, "grant"),
      Grant_archive.text(json, "digest"),
      Grant_archive.text(json, "candidate"),
      Grant_archive.text(json, "ingress"),
      field("size")->Option.flatMap(JSON.Decode.float),
    ) {
    | (Some(at), Some(grant), Some(digest), Some(candidate), Some(ingress), Some(size)) =>
      Some({at, grant, digest, candidate, ingress, size})
    | _ => None
    }
  | exception JsExn(_) => None
  }

// A hold with no digest yet, which no driver call follows until the intent replaces it.
let pending = (t: Context.t, nonce) =>
  encode(
    {
      at: t.store.now(),
      grant: "",
      digest: "",
      candidate: "",
      ingress: "",
      size: 0.,
    },
    ~nonce,
  )

let host = (host: Driver.host) => {
  ...host,
  reach: {
    ...host.reach,
    fetch: request => host.reach.fetch(Web.withSignal(request, {signal: Web.deadline(deadline)})),
  },
}

let release = (lease: t): State.release => {
  hash: lease.digest,
  form: Modules,
  size: lease.size,
  kinds: Some([Function]),
  ingress: ?(
    lease.ingress == ""
      ? None
      : Some(
          JSON.parseOrThrow(lease.ingress)
          ->JSON.Decode.array
          ->Option.getOrThrow
          ->Array.map(item => C.AppIngress.fromJson(item)->Result.getOrThrow),
        )
  ),
}

let same = (kept: State.release, release: State.release) =>
  kept.form == release.form &&
  kept.kinds == release.kinds &&
  Grant_archive.ingressText(kept.ingress) == Grant_archive.ingressText(release.ingress)

let compatible = async (t: Context.t, release: State.release) =>
  switch await t.state.release(release.hash) {
  | None => true
  | Some(kept) => same(kept, release)
  }

let record = async (t: Context.t, app, expected, token, lease: t, ~bytes=?) => {
  switch bytes {
  | Some(bytes) => await t.artifacts.put(lease.digest, bytes)
  | None =>
    switch await t.artifacts.served(Context.stagingKey(lease.grant, lease.digest)) {
    | Some(served) => await t.artifacts.put(lease.digest, await Web.responseBytes(served))
    | None => ()
    }
  }
  await t.state.putRelease(release(lease))
  let recorded = await Grant_store.commit(
    t.store,
    ~app,
    ~expected,
    ~token,
    ~grant=lease.grant,
    ~digest=lease.digest,
    ~candidate=lease.candidate,
  )
  if recorded {
    await Grant_staging.discard(t, lease.grant, lease.digest)
  }
  recorded
}

type told = Silent | Absent | Told(string, C.DeploymentState.t)

let told = async (t: Context.t, app) =>
  switch await t.state.deployment(app) {
  | None => Silent
  | Some(d) =>
    switch await t.state.binding(d.binding) {
    | None => Silent
    | Some(b) =>
      switch Context.host(t, b) {
      | None => Silent
      | Some(driver) =>
        switch await Deploying.described(host(driver), ~app) {
        | exception JsExn(_) => Silent
        | Error({reason: "not_found"}) => Absent
        | Error(_) => Silent
        | Ok(answer) if answer.runs != C.DeploymentRuns.App({id: app}) => Silent
        | Ok(answer) => Told(Envelope.Hex.encode(answer.version), answer.state)
        }
      }
    }
  }

let cleared = (t: Context.t, app, token, lease: t, digest) => {
  Console.error(
    `grant intent on app ${Ids.text(app)} cleared, intent ${lease.digest}, driver ${digest}`,
  )
  Grant_store.releaseLock(t.store, app, token)
}

// Whether the intent is settled, by what the driver says runs.
let judged = async (t: Context.t, app, head: Grant_store.head, lease: t, token) =>
  switch await told(t, app) {
  | Silent => false
  | Told(digest, _) if digest == head.digest =>
    await Grant_store.releaseLock(t.store, app, token)
    true
  | Told(digest, Running(_)) if digest == lease.digest =>
    if lease.grant == "" {
      ignore(
        await Grant_store.adopt(
          t.store,
          ~app,
          ~expected=head.version,
          ~token,
          ~digest,
          ~candidate=lease.candidate,
        ),
      )
    } else {
      ignore(await record(t, app, head.version, token, lease))
    }
    true
  | Told(digest, Making) if digest == lease.digest => false
  | Told(digest, Running(_) | Making | Stopped | Failed(_)) =>
    await cleared(t, app, token, lease, digest)
    true
  | Absent =>
    await cleared(t, app, token, lease, "none")
    true
  }

// Whether the app is free of an unsettled intent, an intent still in its lease counting as free
// since the caller's own lock refuses that. An operator overrides what no definite answer settles.
let reconcile = async (t: Context.t, app, ~override=false) =>
  switch await Grant_store.head(t.store, app) {
  | Some(head) if head.locked != "" =>
    switch decode(head.locked) {
    | Some(lease) if lease.at +. duration > t.store.now() => true
    | Some({digest: ""}) | None =>
      await Grant_store.releaseLock(t.store, app, head.locked)
      true
    | Some(lease) =>
      let nonce = Envelope.Base64url.encode(t.random(16))
      let token = encode({...lease, at: t.store.now()}, ~nonce)
      if await Grant_store.claim(t.store, app, head.locked, token) {
        // The first text goes back on an unknown outcome, so the next finder asks at once.
        let unsettled = async () =>
          if override {
            Console.error(
              `grant intent on app ${Ids.text(
                  app,
                )} cleared by an operator, intent ${lease.digest}, no definite answer`,
            )
            await Grant_store.releaseLock(t.store, app, token)
            true
          } else {
            switch await Grant_store.claim(t.store, app, token, head.locked) {
            | _ => ()
            | exception JsExn(_) => ()
            }
            false
          }
        switch await judged(t, app, head, lease, token) {
        | true => true
        | false => await unsettled()
        | exception JsExn(_) => await unsettled()
        }
      } else {
        true
      }
    }
  | Some(_) | None => true
  }
