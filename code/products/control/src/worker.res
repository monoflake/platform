module Calls = Serve.Calls

/** A port given as text, or the one named. */
let portOf = (given, default) =>
  given->Option.flatMap(text => Int.fromString(text))->Option.getOr(default)

/** The driver's port and the entry's, as the driver names them. */
let driverPort = 37483
let entryPort = 36879

/** No certificate is trusted yet, so a signed call is refused as denied. */
let untrusted = (): Capability.Signed.trust => {
  root: Uint8Array.fromLength(32),
  certificates: [],
  now: 0.,
}

/** Where every host is reached, the address put in place of each where one is configured. */
let reachOf = (env: Stores.env) =>
  switch (env.reach, env.hosts) {
  | (Some(address), _) if address != "" => Some(Reach.local(address))
  | (_, Some(hosts)) => Some(Reach.network(hosts))
  | (_, None) => None
  }

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

let api = async (request, env: Stores.env, ~reach, ~origin, ~path) => {
  let state = State.ofDatabase(env.state)
  let headers = request->Web.requestHeaders
  let header = name => headers->Web.header(name)->Nullable.toOption
  let caller = await callerOf(state, env, request, "authorization")
  let parts: Api.parts = {
    state,
    artifacts: Artifacts.ofBucket(env.artifacts),
    reach,
    tunnels: tunnelsOf(env),
    driverPort: portOf(env.driverPort, driverPort),
    origin,
    wait: () => Web.sleep(250),
  }
  let answer = await Calls.serve(
    Api.routes(parts, caller),
    ~trust=untrusted,
    {
      method_: request->Web.method_,
      path,
      contentType: header("content-type"),
      accept: header("accept"),
      body: await request->Web.bytesOf,
    },
  )
  Web.response(
    answer.body,
    {status: answer.status, headers: dict{"content-type": answer.contentType}},
  )
}

/** An artifact's path, its hash in hex. */
let artifact = /^\/artifacts\/([0-9a-f]{64})$/

let fetch = async (request, env: Stores.env) => {
  let located = Web.parts(request->Web.url)
  let path = located->Web.pathname
  switch reachOf(env) {
  | None => Web.answered(~status=500, "the control is configured with no way to reach a host")
  | Some(reach) =>
    switch (Gateway.routed(path), artifact->RegExp.exec(path), request->Web.method_) {
    | (Some(routed), _, _) =>
      await Gateway.passed(
        State.ofDatabase(env.state),
        reach,
        ~port=portOf(env.entryPort, entryPort),
        request,
        routed,
        ~search=located->Web.search,
      )
    | (None, Some(found), "GET") =>
      switch found->RegExp.Result.matches {
      | [Some(hash)] =>
        switch await Artifacts.ofBucket(env.artifacts).served(hash) {
        | Some(served) => served
        | None => Web.answered(~status=404, `no artifact ${hash} is kept`)
        }
      | _ => Web.answered(~status=404, "no artifact")
      }
    | (None, _, _) =>
      let state = State.ofDatabase(env.state)
      let driverPort = portOf(env.driverPort, driverPort)
      switch (Relay.routed(path), Relay.objected(path)) {
      | (Some(relayed), _) =>
        await Relay.passed(
          state,
          reach,
          ~caller=await callerOf(state, env, request, "proxy-authorization"),
          ~ports=(driverPort, portOf(env.entryPort, entryPort)),
          request,
          relayed,
          ~search=located->Web.search,
        )
      | (None, true) =>
        await Relay.stored(
          state,
          reach,
          ~caller=await callerOf(state, env, request, "authorization"),
          ~port=driverPort,
          request,
          ~path,
        )
      | (None, false) =>
        // A host reaches the control by `ORIGIN` where one is set, as a container on the Mac does.
        await api(
          request,
          env,
          ~reach,
          ~origin=env.origin
          ->Option.filter(o => o != "")
          ->Option.getOr(located->Web.origin),
          ~path,
        )
      }
    }
  }
}

type worker = {fetch: (Web.request, Stores.env) => promise<Web.response>}

let default = {fetch: fetch}
