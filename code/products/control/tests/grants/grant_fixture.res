module C = Envelope.Contracts
open Node

type t = {
  context: Grant_context.t,
  time: ref<float>,
  held: dict<Uint8Array.t>,
  seen: array<JSON.t>,
  effect: ref<unit => promise<unit>>,
}

let candidate = {...Grant_context.emptyCandidate, platform: String.repeat("1", 40)}

let archive = (
  ~metadata=JSON.Object(
    dict{
      "main_module": String("worker.js"),
      "compatibility_date": String("2026-10-21"),
    },
  ),
  ~bytes=Web.utf8("export default {}"),
  (),
) =>
  Grants.tar([
    {name: "metadata.json", bytes: Web.utf8(JSON.stringify(metadata))},
    {name: "worker.js", bytes},
  ])

let make = async (~database=Sqlite.database(), ()) => {
  let time = ref(1000.)
  let store: Grant_store.t = {database, now: () => time.contents}
  let secret = Uint8Array.fromLength(32)
  let state = State.ofDatabase(
    store.database,
    ~sealing=Sealing.ofKey(Some(Envelope.Base64url.encode(secret))),
  )
  let {id: organization} = await state.openOrganization("grant-test", ~secret)
  let binding = await state.openBinding(~organization, ~secret, ~relayed=false, ~random=() =>
    16777226.
  )
  ignore(await state.addressed(~binding, ~address="10.200.0.1"))
  await state.routed(~binding)
  let app = await state.drawApp(~random=() => 16777236.)
  let digest = Envelope.Hex.encode(await Web.sha256(archive()))
  await state.putRelease({hash: digest, form: Modules, size: 2048., kinds: Some([Function])})
  await state.deploy({app, binding, release: digest, capacity: 7., kind: Some(Function)})
  let held = dict{}
  let artifacts: Artifacts.t = {
    put: async (name, bytes) => held->Dict.set(name, bytes),
    delete: async name => held->Dict.delete(name),
    served: async name =>
      held
      ->Dict.get(name)
      ->Option.map(bytes => Web.response(bytes, {status: 200, headers: dict{}})),
  }
  let seen = []
  let effect = ref(async () => ())
  let fetch = async request => {
    let json = JSON.parseOrThrow(Web.fromUtf8(await Web.bytesOf(request)))
    seen->Array.push(json)
    await effect.contents()
    Web.answered(
      ~status=200,
      ~contentType="application/json",
      JSON.stringify(
        JSON.Object(
          dict{
            "status": String("success"),
            "data": C.DeploymentDescribed.toJson({
              runs: App({id: app}),
              version: json
              ->Called.member("input")
              ->Called.member("version")
              ->JSON.Decode.string
              ->Option.flatMap(Envelope.Hex.decode)
              ->Option.getOrThrow,
              state: Running({address: "10.0.0.2:8080", runtime: Workerd, isolation: [Isolate]}),
            }),
          },
        ),
      ),
    )
  }
  let serial = ref(0)
  let context: Grant_context.t = {
    store,
    state,
    artifacts,
    reach: {origin: (~address, ~port) => `http://${address}:${Int.toString(port)}`, fetch},
    direct: fetch,
    driverPort: 37483,
    origin: "https://control.test",
    random: length => {
      serial := serial.contents + 1
      Uint8Array.fromArray(Array.make(~length, serial.contents))
    },
    initialized: () => true,
    ready: () => Grant_store.readable(store),
  }
  {context, time, held, seen, effect}
}

let callJson = async (t, caller, json) => {
  let name = key => json->Called.member(key)->JSON.Decode.string->Option.getOr("")
  let answer = await Serve.Calls.serve(
    [Grant_api.route(t.context, caller)],
    ~trust=Called.untrusted,
    {
      method_: "POST",
      path: `/${name("interface")}/${name("operation")}`,
      contentType: Some("application/json"),
      accept: Some("application/json"),
      body: Web.utf8(JSON.stringify(json)),
    },
  )
  (answer.status, JSON.parseOrThrow(Web.fromUtf8(answer.body)))
}

let envelope = call => C.Interface.DeploymentGrants.toJson({call, capabilities: []})
let call = (t, caller, operation) => callJson(t, caller, envelope(operation))

type minted = {proof: Access.proof, caller: Access.caller, bearer: string}
let mint = async (t, ~health=false, ~expires: float=2000., ()) => {
  let policy: C.DeploymentGrantMintPolicy.t = switch health {
  | true => Health({expires: expires})
  | false => Deploy({app: 16777236., expires})
  }
  let (status, answer) = await call(t, Operator, Mint({policy: policy}))
  deepEqual(status, 200, ~message=JSON.stringify(answer))
  let bytes = answer->Called.data->C.DeploymentGrantMinted.fromJson->Result.getOrThrow
  let bearer = Web.fromUtf8(bytes.bearer)
  let proof: Access.proof = {grant: bytes.grant, verifier: await Web.sha256(Web.utf8(bearer))}
  {proof, bearer, caller: await Grant_context.caller(t.context, proof)}
}

let reason = ((_, json)) => Called.reason(json)
let upload = async (t, minted, ~bytes=archive(), ()) => {
  let digest = await Web.sha256(bytes)
  let answer = await call(t, minted.caller, Upload({artifact: bytes, digest}))
  deepEqual(answer->reason, None, ~message=JSON.stringify(Pair.second(answer)))
  digest
}

let app = 16777236.
let fresh = () =>
  archive(~bytes=Web.utf8("export default {fetch() { return new Response('new') }}"), ())
let version = async t =>
  (await Grant_store.head(t.context.store, app))
  ->Option.getOrThrow
  ->((head: Grant_store.head) => head.version)
let locked = async t =>
  (await Grant_store.head(t.context.store, app))
  ->Option.getOrThrow
  ->((head: Grant_store.head) => head.locked)
let running: C.DeploymentState.t = Running({
  address: "10.0.0.2:8080",
  runtime: Workerd,
  isolation: [Isolate],
})
let answered = (digest, ~state=running) =>
  Host.success(C.DeploymentDescribed.toJson({runs: App({id: app}), version: digest, state}))
let success = digest => answered(digest)
let answering = (t, fetch) => {
  ...t,
  context: {...t.context, reach: {...t.context.reach, fetch}},
}

let releases = async (t, operation) => {
  let stood = Called.stand()
  let parts = {
    ...stood.parts,
    state: t.context.state,
    artifacts: t.context.artifacts,
    reach: t.context.reach,
    direct: t.context.direct,
  }
  let json = Called.releases(operation)
  let name = json->Called.member("operation")->JSON.Decode.string->Option.getOrThrow
  let answer = await Serve.Calls.serve(
    Api.routes(parts, Operator, ~grants=t.context),
    ~trust=Called.untrusted,
    {
      method_: "POST",
      path: `/releases/${name}`,
      contentType: Some("application/json"),
      accept: Some("application/json"),
      body: Web.utf8(JSON.stringify(json)),
    },
  )
  (answer.status, JSON.parseOrThrow(Web.fromUtf8(answer.body)))
}

let retireDriver = (t, ~deleteFails=false) =>
  answering(t, async request =>
    switch Web.parts(Web.url(request))->Web.pathname {
    | "/deployments/delete" =>
      deleteFails
        ? Web.answered(
            ~status=400,
            ~contentType="application/json",
            "{\"status\":\"error\",\"failure\":\"rejected\",\"reason\":\"still_running\",\"message\":\"it runs\"}",
          )
        : Host.success(C.DeploymentDeleted.toJson({}))
    | _ => success(await Web.sha256(fresh()))
    }
  )

// An intent as a holder that died leaves it, its five minutes passed.
let lapsed = async (t, grant, digest) => {
  let text = JSON.stringify(
    JSON.Object(
      dict{
        "at": Number(t.time.contents),
        "grant": String(grant.proof.grant),
        "digest": String(Envelope.Hex.encode(digest)),
        "candidate": String(JSON.stringify(C.DeploymentCandidate.toJson(candidate))),
        "ingress": String(""),
        "size": Number(Int.toFloat(fresh()->TypedArray.length)),
      },
    ),
  )
  await Grant_store.run(
    t.context.store,
    "UPDATE grant_head SET locked = ? WHERE app = ?",
    [Text(text), Number(app)],
  )
  t.time := t.time.contents +. 300000.
}

type countRow = {count: int}

let count = async (t, table) => {
  let found: option<countRow> = await Grant_store.first(
    t.context.store,
    `SELECT COUNT(*) AS count FROM ${table}`,
    [],
  )
  found->Option.getOrThrow->(value => value.count)
}
