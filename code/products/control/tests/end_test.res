/***
 * The control run by `wrangler dev` on workerd with local D1 and R2, a host and Cloudflare's API
 * faked on the loopback, and hello deployed through it and asked through the gateway, RFC rxmd9.
 */
open Node
module Contracts = Envelope.Contracts

let block = fromRoot("code/products/control")
let hello = fromRoot("../cloud/apps/hello")
let wrangler = join([block, "node_modules", ".bin", "wrangler"])

let quiet = () => {
  let given = Dict.copy(env)
  given->Dict.set("WRANGLER_SEND_METRICS", "false")
  given->Dict.set("CI", "1")
  // Miniflare would otherwise fetch the request's `cf` object from Cloudflare.
  given->Dict.set("CLOUDFLARE_CF_FETCH_ENABLED", "false")
  ["CLOUDFLARE_API_TOKEN", "CLOUDFLARE_ACCOUNT_ID"]->Array.forEach(k => given->Dict.delete(k))
  given
}

let orThrow = result =>
  switch result {
  | Ok(value) => value
  | Error(why) => JsError.throwWithMessage(why)
  }

/** hello built by its own wrangler and packed by deploy's bundle, as `mise run deploy` packs it. */
let helloArchive = async scratch => {
  ran(fromRoot("node_modules/.bin/rescript"), ["build", "code/tools/deploy"], ~cwd=fromRoot(""))
  ->orThrow
  ->ignore
  let out = join([scratch, "hello"])
  ran(
    join([hello, "node_modules", ".bin", "wrangler"]),
    ["deploy", "--dry-run", "--outdir", out],
    ~cwd=hello,
    ~env=quiet(),
  )
  ->orThrow
  ->ignore
  let bundle = await bundle()
  let config = bundle.config(readText(join([hello, "wrangler.jsonc"])))->orThrow
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

let freePort = async () => {
  let (server, port) = await listening((_, _) => ())
  await shut(server)
  port
}

/** Asked until it answers anything, a minute at most. */
let rec answering = async (url, ~left=240) =>
  switch await Web.fetch(Web.request(url, {method: "GET", headers: dict{}})) {
  | _ => ()
  | exception JsExn(_) if left > 0 =>
    await Web.sleep(250)
    await answering(url, ~left=left - 1)
  | exception JsExn(e) => throw(JsExn(e))
  }

let operator = "the operator's secret"

let call = async (origin, ~bearer, envelope) => {
  let named = key =>
    envelope
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get(key))
    ->Option.flatMap(JSON.Decode.string)
    ->Option.getOr("")
  let answer = await Web.fetch(
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

test("hello opened, bound, put, deployed and asked through a control on workerd", async () => {
  ok(exists(hello), ~message=`${hello} holds hello, the cloud repository cloned beside this one`)
  let scratch = mkdtemp(join([tmpdir(), "control-"]))
  let host = Host.make()
  let calls = []
  let (driver, driverPort) = await listening(served(host.reach.fetch))
  let helloPort = await freePort()
  let helloOrigin = `http://127.0.0.1:${Int.toString(helloPort)}`
  // The entry hands the app's host to hello itself, once deployed, as the real entry would.
  let entered = async request => {
    let named = request->Web.requestHeaders->Web.header("x-forwarded-host")->Nullable.toOption
    switch (host.deployed.contents, named) {
    | (Some(_), Some("app-1.b1")) =>
      let at = Web.parts(request->Web.url)
      await Web.fetch(Web.resent(`${helloOrigin}${at->Web.pathname}${at->Web.search}`, request))
    | _ => await host.reach.fetch(request)
    }
  }
  let (entry, entryPort) = await listening(served(entered))
  let (cloudflare, apiPort) = await listening(served(api(calls)))
  let port = await freePort()
  let persisted = join([scratch, "state"])
  let dev = ref(None)
  let helloDev = ref(None)
  let finished = async () => {
    switch dev.contents {
    | Some(child) => await stopped(child)
    | None => ()
    }
    switch helloDev.contents {
    | Some(child) => await stopped(child)
    | None => ()
    }
    await shut(driver)
    await shut(entry)
    await shut(cloudflare)
    rm(scratch, {recursive: true, force: true})
  }
  try {
    let archive = await helloArchive(scratch)
    helloDev :=
      Some(
        spawn(
          join([hello, "node_modules", ".bin", "wrangler"]),
          [
            "dev",
            "--ip",
            "127.0.0.1",
            "--port",
            Int.toString(helloPort),
            "--persist-to",
            join([scratch, "hello-state"]),
            "--show-interactive-dev-session=false",
          ],
          {cwd: hello, env: quiet(), stdio: ["ignore", "ignore", "ignore"]},
        ),
      )
    ran(
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
      ~env=quiet(),
    )
    ->orThrow
    ->ignore
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
    dev :=
      Some(
        spawn(
          wrangler,
          Array.concat(
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
          {cwd: block, env: quiet(), stdio: ["ignore", "ignore", "ignore"]},
        ),
      )
    // Called by another name than ORIGIN, so the artifact's address shows which was taken.
    let origin = `http://localhost:${Int.toString(port)}`
    await answering(`${origin}/`)
    await answering(`${helloOrigin}/`)
    let organization = await call(
      origin,
      ~bearer=operator,
      Contracts.Interface.Organizations.toJson({call: Open({label: "first"}), capabilities: []}),
    )
    let opened = await call(
      origin,
      ~bearer=operator,
      Contracts.Interface.Bindings.toJson({
        call: Open({organization: organization->number("organization")}),
        capabilities: [],
      }),
    )
    let token = `${Float.toString(opened->number("binding"))}.${opened->text("secret")}`
    let bound = await call(
      origin,
      ~bearer=token,
      Contracts.Interface.Bindings.toJson({call: Bind({}), capabilities: []}),
    )
    deepEqual(
      (
        bound->text("address"),
        bound->text("tunnel")->Envelope.Base64url.decode->Option.map(Web.fromUtf8),
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
      origin,
      ~bearer=operator,
      Contracts.Interface.Releases.toJson({
        call: Deploy({
          binding: opened->number("binding"),
          app: 1.,
          release: Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0)),
        }),
        capabilities: [],
      }),
    )
    deepEqual(deployed->member("state")->member("name"), JSON.String("running"))
    // What the driver was handed is fetched from the control as the driver would fetch it.
    let address = host.deployed.contents->Option.mapOr("", d => d.artifact.address)
    deepEqual(address, `http://127.0.0.1:${Int.toString(port)}/artifacts/${hash}`)
    let fetched = await Web.fetch(Web.request(address, {method: "GET", headers: dict{}}))
    deepEqual(Envelope.Hex.encode(await Web.sha256(await fetched->Web.responseBytes)), hash)
    let described = await call(
      origin,
      ~bearer=operator,
      Contracts.Interface.Releases.toJson({call: Describe({app: 1.}), capabilities: []}),
    )
    deepEqual(described, deployed)
    let direct = await (
      await Web.fetch(Web.request(`${helloOrigin}/`, {method: "GET", headers: dict{}}))
    )->Web.text
    ok(direct->String.startsWith("hello from "), ~message=`hello answered ${direct}`)
    let asked = await Web.fetch(
      Web.request(`${origin}/v1/app-1/`, {method: "GET", headers: dict{}}),
    )
    deepEqual((asked->Web.status, await asked->Web.text), (200, direct))
    await finished()
  } catch {
  | e =>
    await finished()
    throw(e)
  }
})
