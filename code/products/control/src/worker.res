module Calls = Serve.Calls

/** A port given as text, or the one named. */
let portOf = (given, default) =>
  given->Option.flatMap(text => Int.fromString(text))->Option.getOr(default)

/** No certificate is trusted yet, so a signed call is refused as denied. */
let untrusted = (): Capability.Signed.trust => {
  root: Uint8Array.fromLength(32),
  certificates: [],
  now: 0.,
}

/** Where every host is reached, the address put in place of each where one is configured. */
let reachOf = Reach.configured

let tunnelsOf = (env: Stores.env) =>
  switch (env.tunnelAccount, env.tunnelCredential) {
  | (Some(account), Some(credential)) if account != "" && credential != "" =>
    Some(
      Tunnels.through(
        {
          api: env.tunnelApi->Option.getOr("https://api.cloudflare.com/client/v4"),
          account,
          credential,
        },
        Web.fetch,
      ),
    )
  | _ => None
  }

/** What the control stands on, its own stores, or the control it is an organization of. */
type stood = {
  state: State.t,
  artifacts: Artifacts.t,
  reach: Reach.t,
  tunnels: option<Tunnels.t>,
  standing: option<Standing.t>,
  /** Whether it gives organizations a relay and objects, as only a control with stores does. */
  gives: bool,
}

let stoodOf = (env: Stores.env) =>
  switch (env.standsOn, env.standsOnToken) {
  | (Some(origin), Some(token)) if origin != "" && token != "" =>
    let objects = Objects.through(~origin, ~token, Web.fetch)
    Ok({
      state: State.ofObjects(objects, ~sealing=Sealing.ofKey(env.sealingKey)),
      artifacts: Artifacts.ofObjects(objects),
      reach: reachOf(env)->Option.getOrThrow,
      tunnels: None,
      standing: Some(Standing.through(~origin, ~token, Web.fetch)),
      gives: false,
    })
  | _ =>
    switch (env.state, env.artifacts, reachOf(env)) {
    | (Some(database), Some(bucket), Some(reach)) =>
      Ok({
        state: State.ofDatabase(database, ~sealing=Sealing.ofKey(env.sealingKey)),
        artifacts: Artifacts.ofBucket(bucket),
        reach,
        tunnels: tunnelsOf(env),
        standing: None,
        gives: true,
      })
    | _ => Error("the control is configured with no stores, or no way to reach a host")
    }
  }

/** Who presented the credential a header carries. */
let callerOf = (state: State.t, env: Stores.env, request, name) =>
  Access.caller(
    request->Web.requestHeaders->Web.header(name)->Nullable.toOption,
    ~operator=env.operator,
    ~secret=async id =>
      switch await state.binding(id) {
      | Some({relayed: false, secret}) => Some(secret)
      | Some({relayed: true}) | None => None
      },
    ~organizationSecret=state.organizationSecret,
  )

let api = async (request, env: Stores.env, stood, ~origin, ~path) => {
  let headers = request->Web.requestHeaders
  let header = name => headers->Web.header(name)->Nullable.toOption
  let parts: Api.parts = {
    state: stood.state,
    artifacts: stood.artifacts,
    reach: stood.reach,
    tunnels: stood.tunnels,
    standing: stood.standing,
    driverPort: portOf(env.driverPort, Reach.driverPort),
    // Called as a method, the global fetch would be given a receiver workerd refuses.
    direct: request => Web.fetch(request),
    origin,
    wait: () => Web.sleep(250),
  }
  let grants = env.state->Option.map(database => {
    let store: Grant_store.t = {database, now: Date.now}

    (
      {
        store,
        state: stood.state,
        artifacts: stood.artifacts,
        reach: stood.reach,
        direct: parts.direct,
        driverPort: parts.driverPort,
        origin,
        random: Web.random,
        initialized: () => stood.gives,
        ready: () => Grant_store.readable(store),
      }: Grant_context.t
    )
  })
  let authenticate = async () =>
    await Access.caller(
      header("authorization"),
      ~operator=env.operator,
      ~secret=async id =>
        switch await stood.state.binding(id) {
        | Some({relayed: false, secret}) => Some(secret)
        | Some({relayed: true}) | None => None
        },
      ~organizationSecret=stood.state.organizationSecret,
      ~grant=proof =>
        grants->Option.mapOr(Promise.resolve(Access.Nobody), t => Grant_context.caller(t, proof)),
    )
  let caller = path->String.startsWith("/deployment_grants/") ? Access.Nobody : await authenticate()
  let body =
    path->String.startsWith("/deployment_grants/")
      ? await Web.limitedBytes(request, path == "/deployment_grants/upload" ? 47185920 : 8192)
      : Some(await Web.bytesOf(request))
  let answer = switch body {
  | None =>
    (
      {
        status: 413,
        contentType: "application/json",
        body: Web.utf8(
          JSON.stringify(
            Envelope.Contracts.Answer.toJson(
              Error({failure: Rejected, reason: "too_large", message: "request exceeds its bound"}),
              _ => JSON.Null,
            ),
          ),
        ),
      }: Calls.response
    )

  | Some(body) =>
    await Calls.serve(
      Api.routes(parts, caller, ~grants?, ~grantCaller=authenticate),
      ~trust=untrusted,
      {
        method_: request->Web.method_,
        path,
        contentType: header("content-type"),
        accept: header("accept"),
        body,
      },
    )
  }
  Web.response(
    answer.body,
    {
      status: answer.status,
      headers: dict{"content-type": answer.contentType, "cache-control": "no-store"},
    },
  )
}

/** An artifact's path, its hash in hex. */
let artifact = /^\/artifacts\/([0-9a-f]{64})$/

/** A staged artifact's path, its grant, its hash in hex and its fetch token. */
let staging = /^\/artifacts\/staging\/([A-Za-z0-9_-]+)\/([0-9a-f]{64})\/([A-Za-z0-9_-]+)$/

let stagedAnswer = async (stood, env: Stores.env, found) =>
  switch (found->RegExp.Result.matches, env.state) {
  | ([Some(grant), Some(digest), Some(token)], Some(database)) =>
    let store: Grant_store.t = {database, now: Date.now}
    switch await Grant_staging.served(store, stood.artifacts, ~grant, ~digest, ~token) {
    | Some(served) => served
    | None => Web.answered(~status=404, "no artifact")
    | exception JsExn(_) => Web.answered(~status=503, "no artifact is read now")
    }
  | _ => Web.answered(~status=404, "no artifact")
  }

let called = path =>
  switch path {
  | "/organizations/open"
  | "/bindings/open"
  | "/bindings/bind"
  | "/reaches/open"
  | "/releases/put"
  | "/releases/deploy"
  | "/releases/describe"
  | "/releases/forget"
  | "/releases/retire"
  | "/deployment_grants/mint"
  | "/deployment_grants/revoke"
  | "/deployment_grants/upload"
  | "/deployment_grants/deploy"
  | "/deployment_grants/status"
  | "/deployment_grants/health" => true
  | _ => false
  }

let healthFallback = (env: Stores.env): option<stood> =>
  env.state->Option.map(database => {
    state: State.ofDatabase(database, ~sealing=Sealing.ofKey(env.sealingKey)),
    artifacts: {
      put: async (_, _) => JsError.throwWithMessage("unavailable"),
      delete: async _ => JsError.throwWithMessage("unavailable"),
      served: async _ => None,
    },
    reach: {
      origin: (~address as _, ~port as _) => "https://unavailable.invalid",
      fetch: async _ => JsError.throwWithMessage("unavailable"),
    },
    tunnels: None,
    standing: None,
    gives: false,
  })

let answered = async (request, env: Stores.env) => {
  let located = Web.parts(request->Web.url)
  let path = located->Web.pathname
  let method_ = request->Web.method_
  if (
    !(method_ == "POST" && called(path)) &&
    !(method_ == "GET" && (artifact->RegExp.test(path) || staging->RegExp.test(path))) &&
    Relay.routed(path) == None &&
    !Relay.objected(path)
  ) {
    Web.answered(~status=404, "not found")
  } else {
    switch stoodOf(env) {
    | Error(why) =>
      if path == "/deployment_grants/health" {
        switch healthFallback(env) {
        | Some(stood) =>
          await api(
            request,
            env,
            stood,
            ~origin=env.origin->Option.getOr(located->Web.origin),
            ~path,
          )
        | None =>
          Web.answered(
            ~status=403,
            ~contentType="application/json",
            "{\"status\":\"error\",\"failure\":\"rejected\",\"reason\":\"denied\",\"message\":\"denied\"}",
          )
        }
      } else {
        Web.answered(~status=500, why)
      }
    | Ok(stood) =>
      let driverPort = portOf(env.driverPort, Reach.driverPort)
      switch (artifact->RegExp.exec(path), staging->RegExp.exec(path), method_) {
      | (_, Some(found), "GET") => await stagedAnswer(stood, env, found)
      | (Some(found), _, "GET") =>
        switch found->RegExp.Result.matches {
        | [Some(hash)] =>
          switch await stood.artifacts.served(hash) {
          | Some(served) => served
          | None => Web.answered(~status=404, `no artifact ${hash} is kept`)
          }
        | _ => Web.answered(~status=404, "no artifact")
        }
      | (_, _, _) =>
        switch (stood.gives, Relay.routed(path), Relay.objected(path)) {
        | (true, Some(relayed), _) =>
          await Relay.passed(
            stood.state,
            stood.reach,
            ~caller=await callerOf(stood.state, env, request, "proxy-authorization"),
            ~ports=[driverPort, portOf(env.entryPort, Reach.entryPort)],
            request,
            relayed,
            ~search=located->Web.search,
          )
        | (true, None, true) =>
          await Relay.stored(
            stood.state,
            stood.reach,
            ~caller=await callerOf(stood.state, env, request, "authorization"),
            ~port=driverPort,
            ~wait=() => Web.sleep(250),
            request,
            ~path,
          )
        | _ if method_ == "POST" && called(path) =>
          // A host reaches the control by `ORIGIN` where one is set,
          // as a container on the Mac does.
          await api(
            request,
            env,
            stood,
            ~origin=env.origin
            ->Option.filter(o => o != "")
            ->Option.getOr(located->Web.origin),
            ~path,
          )
        | _ => Web.answered(~status=404, "not found")
        }
      }
    }
  }
}

type worker = {fetch: (Web.request, Stores.env) => promise<Web.response>}

let default = {
  fetch: async (request, env) => {
    let response = await answered(request, env)
    let path = Web.parts(Web.url(request))->Web.pathname
    if (
      path->String.startsWith("/deployment_grants/") ||
        path->String.startsWith("/artifacts/staging/")
    ) {
      response->Web.responseHeaders->Web.setHeader("cache-control", "no-store")
    }
    response
  },
}
