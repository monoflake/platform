/***
 * The gateway and control run apart on workerd with the same local D1, hello reached through
 * the gateway alone, RFC oomwh.
 */
module Ids = ControlOrganization.Ids
open Node
module Contracts = Envelope.Contracts

let block = fromRoot("code/products/control")
let gateway = fromRoot("code/products/gateway")
let hello = fromRoot("code/products/gateway/tests/fixtures")
let wrangler = join([block, "node_modules", ".bin", "wrangler"])

let orThrow = result =>
  switch result {
  | Ok(value) => value
  | Error(why) => JsError.throwWithMessage(why)
  }

// The local hello fixture is bundled and packed as an app would be.
let helloArchive = async (scope, scratch) => {
  await Rehearsal.ran(
    scope,
    fromRoot("node_modules/.bin/rescript"),
    ["build", "code/tools/deploy"],
    ~cwd=fromRoot(""),
  )
  let out = join([scratch, "hello"])
  await Rehearsal.ran(scope, wrangler, ["deploy", "--dry-run", "--outdir", out], ~cwd=hello)
  let bundle = await bundle()
  let config = bundle.config(readText(join([hello, "wrangler.json"])))->orThrow
  let files =
    list(out, {recursive: true})
    ->Array.filter(name => stat(join([out, name]))->isFile)
    ->Array.map((name): bundled => {name, bytes: readBytes(join([out, name]))})
  bundle.packed(config, files)->orThrow
}

/** A node request answered by a fetch handler, as the Worker's fetch would reach it. */
let served = (handle: Web.fetch) =>
  (request, response) => {
    let answered = async () => {
      let headers = request->requestHeaders->Dict.copy
      ["connection", "content-length", "transfer-encoding", "keep-alive"]->Array.forEach(k =>
        headers->Dict.delete(k)
      )
      let bytes = await body(request)
      let url = `http://${headers->Dict.get("host")->Option.getOr("127.0.0.1")}${request->path}`
      let init: Web.requestInit =
        request->method == "GET" || request->method == "HEAD"
          ? {method: request->method, headers}
          : {method: request->method, headers, body: bytes}
      let answer = await handle(Web.request(url, init))
      let contentType =
        answer->Web.responseHeaders->Web.header("content-type")->Nullable.toOption->Option.getOr("")
      response->writeHead(answer->Web.status, dict{"content-type": contentType})
      response->end(await answer->Web.responseBytes)
    }
    answered()->ignore
  }

/** Cloudflare's API faked, each call kept by its method and path. */
let api = calls =>
  async request => {
    let path = Web.parts(request->Web.url)->Web.pathname
    calls->Array.push(`${request->Web.method_} ${path}`)
    let result = switch (request->Web.method_, path->String.endsWith("/token")) {
    | ("GET", true) => JSON.String("e2e-token")
    | _ => JSON.parseOrThrow(`{"id": "e2e-tunnel"}`)
    }
    Web.answered(
      ~status=200,
      ~contentType="application/json",
      JSON.stringify(JSON.Object(dict{"success": Boolean(true), "result": result})),
    )
  }

let operator = "the operator's secret"

let call = async (scope, origin, ~bearer, envelope) => {
  let named = key =>
    envelope
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get(key))
    ->Option.flatMap(JSON.Decode.string)
    ->Option.getOr("")
  let answer = await Rehearsal.fetch(
    scope,
    Web.request(
      `${origin}/${named("interface")}/${named("operation")}`,
      {
        method: "POST",
        headers: dict{
          "authorization": `Bearer ${bearer}`,
          "content-type": "application/json",
          "accept": "application/json",
        },
        body: Web.utf8(JSON.stringify(envelope)),
      },
    ),
  )
  let text = await answer->Web.text
  switch JSON.parseOrThrow(text)->JSON.Decode.object {
  | Some(o) if o->Dict.get("status") == Some(String("success")) =>
    o->Dict.get("data")->Option.getOr(JSON.Null)
  | _ => JsError.throwWithMessage(`${named("interface")}.${named("operation")} answered ${text}`)
  }
}

let member = (json, name) =>
  json->JSON.Decode.object->Option.flatMap(o => o->Dict.get(name))->Option.getOr(JSON.Null)
let number = (json, name) => json->member(name)->JSON.Decode.float->Option.getOr(0.)
let text = (json, name) => json->member(name)->JSON.Decode.string->Option.getOr("")

test("hello deployed through the control is reached through the gateway Worker alone", async () => {
  await Rehearsal.using(async scope => {
    let scratch = Rehearsal.scratch(scope)
    let host = Host.make()
    let calls = []
    let (_, driverPort) = await Rehearsal.listening(scope, served(host.reach.fetch))
    let helloPort = await Rehearsal.freePort()
    let helloOrigin = `http://127.0.0.1:${Int.toString(helloPort)}`
    // The entry hands the app's host to hello itself, once deployed, as the real entry would.
    let binding = ref(0.)
    let entered = async request => {
      let named = request->Web.requestHeaders->Web.header("x-forwarded-host")->Nullable.toOption
      let app = switch host.deployed.contents->Option.map(d => d.runs) {
      | Some(App({id})) => Some(Gateway.host(~app=id, ~binding=binding.contents))
      | Some(Component(_)) | None => None
      }
      switch (app, named) {
      | (Some(app), Some(named)) if named == app =>
        let at = Web.parts(request->Web.url)
        await Rehearsal.fetch(
          scope,
          Web.resent(`${helloOrigin}${at->Web.pathname}${at->Web.search}`, request),
        )
      | _ => await host.reach.fetch(request)
      }
    }
    let (_, entryPort) = await Rehearsal.listening(scope, served(entered))
    let (_, apiPort) = await Rehearsal.listening(scope, served(api(calls)))
    let port = await Rehearsal.freePort()
    let persisted = join([scratch, "state"])
    let gatewayPort = await Rehearsal.freePort()
    let archive = await helloArchive(scope, scratch)
    await Rehearsal.dev(
      scope,
      ~name="hello",
      ~program=wrangler,
      ~args=[
        "dev",
        "--ip",
        "127.0.0.1",
        "--port",
        Int.toString(helloPort),
        "--persist-to",
        join([scratch, "hello-state"]),
        "--show-interactive-dev-session=false",
      ],
      ~cwd=hello,
      ~url=helloOrigin,
    )
    await Rehearsal.ran(
      scope,
      wrangler,
      [
        "d1",
        "migrations",
        "apply",
        "STATE",
        "--local",
        "--env",
        "local",
        "--persist-to",
        persisted,
      ],
      ~cwd=block,
    )
    let vars = [
      `OPERATOR:${operator}`,
      `SEALING_KEY:${Envelope.Base64url.encode(Web.random(32))}`,
      `DRIVER_PORT:${Int.toString(driverPort)}`,
      `ENTRY_PORT:${Int.toString(entryPort)}`,
      `TUNNEL_API:http://127.0.0.1:${Int.toString(apiPort)}/client/v4`,
      "TUNNEL_ACCOUNT:account",
      "TUNNEL_CREDENTIAL:credential",
      "REACH:127.0.0.1",
      `ORIGIN:http://127.0.0.1:${Int.toString(port)}`,
    ]
    await Rehearsal.dev(
      scope,
      ~name="control",
      ~program=wrangler,
      ~args=Array.concat(
        [
          "dev",
          "--env",
          "local",
          "--ip",
          "127.0.0.1",
          "--port",
          Int.toString(port),
          "--persist-to",
          persisted,
          "--show-interactive-dev-session=false",
        ],
        vars->Array.flatMap(v => ["--var", v]),
      ),
      ~cwd=block,
      ~url=`http://localhost:${Int.toString(port)}`,
    )
    await Rehearsal.dev(
      scope,
      ~name="gateway",
      ~program=wrangler,
      ~args=[
        "dev",
        "--config",
        join([gateway, "wrangler.json"]),
        "--ip",
        "127.0.0.1",
        "--port",
        Int.toString(gatewayPort),
        "--persist-to",
        persisted,
        "--show-interactive-dev-session=false",
        "--var",
        "REACH:localhost",
        "--var",
        `ENTRY_PORT:${Int.toString(entryPort)}`,
      ],
      ~cwd=gateway,
      ~url=`http://localhost:${Int.toString(gatewayPort)}`,
    )
    let gatewayOrigin = `http://localhost:${Int.toString(gatewayPort)}`
    // Called by another name than ORIGIN, so the artifact's address shows which was taken.
    let origin = `http://localhost:${Int.toString(port)}`
    let organization = await call(
      scope,
      origin,
      ~bearer=operator,
      Contracts.Interface.Organizations.toJson({call: Open({label: "first"}), capabilities: []}),
    )
    let opened = await call(
      scope,
      origin,
      ~bearer=operator,
      Contracts.Interface.Bindings.toJson({
        call: Open({organization: organization->number("organization")}),
        capabilities: [],
      }),
    )
    binding := opened->number("binding")
    let token = `${Float.toString(binding.contents)}.${opened->text("secret")}`
    let bound = await call(
      scope,
      origin,
      ~bearer=token,
      Contracts.Interface.Bindings.toJson({call: Bind({reach: Tunnel}), capabilities: []}),
    )
    deepEqual(
      (
        bound->member("reached")->text("address"),
        bound
        ->member("reached")
        ->text("tunnel")
        ->Envelope.Base64url.decode
        ->Option.map(Web.fromUtf8),
      ),
      ("10.200.0.1", Some("e2e-token")),
    )
    deepEqual(
      calls,
      [
        "POST /client/v4/accounts/account/cfd_tunnel",
        "POST /client/v4/accounts/account/teamnet/routes",
        "GET /client/v4/accounts/account/cfd_tunnel/e2e-tunnel/token",
      ],
    )
    let held = await call(
      scope,
      origin,
      ~bearer=operator,
      Contracts.Interface.Releases.toJson({
        call: Put({form: Modules, artifact: archive}),
        capabilities: [],
      }),
    )
    let hash = held->text("hash")
    deepEqual(hash, Envelope.Hex.encode(await Web.sha256(archive)))
    let deployed = await call(
      scope,
      origin,
      ~bearer=operator,
      Contracts.Interface.Releases.toJson({
        call: Deploy({
          binding: opened->number("binding"),
          release: Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0)),
        }),
        capabilities: [],
      }),
    )
    deepEqual(deployed->member("state")->member("name"), JSON.String("running"))
    // No app was named, so the control drew its id and answered it.
    let app = deployed->member("runs")->number("id")
    // What the driver was handed is fetched from the control as the driver would fetch it.
    let address = host.deployed.contents->Option.mapOr("", d => d.artifact.address)
    deepEqual(address, `http://127.0.0.1:${Int.toString(port)}/artifacts/${hash}`)
    let fetched = await Rehearsal.fetch(
      scope,
      Web.request(address, {method: "GET", headers: dict{}}),
    )
    deepEqual(Envelope.Hex.encode(await Web.sha256(await fetched->Web.responseBytes)), hash)
    let described = await call(
      scope,
      origin,
      ~bearer=operator,
      Contracts.Interface.Releases.toJson({call: Describe({app: app}), capabilities: []}),
    )
    deepEqual(described, deployed)
    let direct = await (
      await Rehearsal.fetch(scope, Web.request(`${helloOrigin}/`, {method: "GET", headers: dict{}}))
    )->Web.text
    ok(direct->String.startsWith("hello from "), ~message=`hello answered ${direct}`)
    let asked = await Rehearsal.fetch(
      scope,
      Web.request(`${gatewayOrigin}/v1/${Ids.text(app)}/`, {method: "GET", headers: dict{}}),
    )
    deepEqual((asked->Web.status, await asked->Web.text), (200, direct))
    let refused = await Rehearsal.fetch(
      scope,
      Web.request(`${origin}/v1/${Ids.text(app)}/`, {method: "GET", headers: dict{}}),
    )
    deepEqual(refused->Web.status, 404)
  })
})
