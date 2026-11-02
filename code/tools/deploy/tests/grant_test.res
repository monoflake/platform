open Node
module Contracts = Envelope.Contracts

let candidate: Contracts.DeploymentCandidate.t = {
  platform: String.repeat("a", 40),
  cloud: String.repeat("b", 40),
  driver: String.repeat("c", 40),
  machine: String.repeat("d", 40),
}

let args = [
  "apps/hello",
  "control:https://control.example",
  "--expected-version",
  "7",
  "--platform",
  candidate.platform,
  "--cloud",
  candidate.cloud,
  "--driver",
  candidate.driver,
  "--machine",
  candidate.machine,
]

let artifact =
  Bundle.packed(
    {main: "index.js", compatibilityDate: "2026-10-21", compatibilityFlags: []},
    [{name: "index.js", bytes: Bytes.utf8("export default {};")}],
  )->Result.getOrThrow
let digest = Host.sha256(artifact)

let success = data =>
  JSON.stringify(JSON.Object(dict{"status": JSON.String("success"), "data": data}))
let described = (~digest=digest, ~candidate=candidate, ~version=8., ()) =>
  success(Contracts.DeploymentGrantDescribed.toJson({app: 1., digest, version, candidate}))

let faked = (~uploadRefused=false, ~stale=false, ~pending=false, ~status=described(), ()) => {
  let operations = []
  let grant: Grant.t = {
    origin: "https://control.example",
    bearer: "fake deployment proof",
    fetch: async (url, init) => {
      ok(init.headers->Dict.get("authorization") == Some("Bearer fake deployment proof"))
      deepEqual(init.redirect, Some("error"))
      let request = init.body->Option.getOrThrow->JSON.parseOrThrow
      let envelope = Contracts.Interface.DeploymentGrants.fromJson(request)->Result.getOrThrow
      let input =
        request
        ->JSON.Decode.object
        ->Option.getOrThrow
        ->Dict.get("input")
        ->Option.getOrThrow
        ->JSON.Decode.object
        ->Option.getOrThrow
      let (operation, keys, body, code) = switch envelope.call {
      | Upload(upload) =>
        deepEqual(Envelope.Hex.encode(upload.artifact), Envelope.Hex.encode(artifact))
        deepEqual(Envelope.Hex.encode(upload.digest), Envelope.Hex.encode(digest))
        (
          "upload",
          ["artifact", "digest"],
          uploadRefused
            ? "fake deployment proof"
            : success(Contracts.DeploymentGrantArtifact.toJson({digest, expires: 12345.})),
          uploadRefused ? 403 : 200,
        )
      | Deploy(deploy) =>
        deepEqual(Envelope.Hex.encode(deploy.digest), Envelope.Hex.encode(digest))
        deepEqual((deploy.expected, deploy.candidate), (7., candidate))
        (
          "deploy",
          ["candidate", "digest", "expected"],
          stale
            ? `{"status":"error","failure":"rejected","reason":"stale","message":"fake deployment proof"}`
            : described(),
          200,
        )
      | Status(_) => (
          "status",
          [],
          pending && operations->Array.length == 2 ? described(~version=7., ()) : status,
          200,
        )
      | Mint(_) | Revoke(_) | Health(_) => JsError.throwWithMessage("unexpected operation")
      }
      deepEqual(input->Dict.keysToArray->Array.toSorted(String.compare), keys)
      deepEqual(url, `https://control.example/deployment_grants/${operation}`)
      operations->Array.push(operation)
      response(body, {"status": code})
    },
  }
  (grant, operations)
}

testAsync("grant uploads Modules deploys expected version and proves scoped status", async () => {
  let (grant, operations) = faked()
  deepEqual(await Grant.deploy(grant, ~artifact, ~expected=7., ~candidate), Ok())
  deepEqual(operations, ["upload", "deploy", "status"])
})

testAsync("grant status refuses another digest", async () => {
  let (grant, operations) = faked(~status=described(~digest=Uint8Array.fromLength(32), ()), ())
  ok((await Grant.deploy(grant, ~artifact, ~expected=7., ~candidate))->Result.isError)
  deepEqual(operations, ["upload", "deploy", "status"])
})

testAsync("grant status refuses each different candidate commit", async () => {
  let candidates = [
    {...candidate, platform: String.repeat("e", 40)},
    {...candidate, cloud: String.repeat("e", 40)},
    {...candidate, driver: String.repeat("e", 40)},
    {...candidate, machine: String.repeat("e", 40)},
  ]
  for at in 0 to candidates->Array.length - 1 {
    let changed = candidates->Array.getUnsafe(at)
    let (grant, operations) = faked(~status=described(~candidate=changed, ()), ())
    ok((await Grant.deploy(grant, ~artifact, ~expected=7., ~candidate))->Result.isError)
    deepEqual(operations, ["upload", "deploy", "status"])
  }
})

testAsync("grant status polls until the expected deployment version is visible", async () => {
  let (grant, operations) = faked(~pending=true, ())
  deepEqual(await Grant.deploy(grant, ~artifact, ~expected=7., ~candidate), Ok())
  deepEqual(operations, ["upload", "deploy", "status", "status"])
})

testAsync(
  "grant status refuses a later concurrent deployment even with matching bytes",
  async () => {
    let (grant, operations) = faked(~status=described(~version=9., ()), ())
    ok((await Grant.deploy(grant, ~artifact, ~expected=7., ~candidate))->Result.isError)
    deepEqual(operations, ["upload", "deploy", "status"])
  },
)

testAsync("a stale grant deploy stops without status or a retry", async () => {
  let (grant, operations) = faked(~stale=true, ())
  let result = await Grant.deploy(grant, ~artifact, ~expected=7., ~candidate)
  ok(result->Result.isError)
  ok(result->Result.mapError(why => !(why->String.includes(grant.bearer))) == Error(true))
  deepEqual(operations, ["upload", "deploy"])
})

testAsync("a refused grant upload stops before deploy and hides the response", async () => {
  let (grant, operations) = faked(~uploadRefused=true, ())
  let result = await Grant.deploy(grant, ~artifact, ~expected=7., ~candidate)
  ok(result->Result.isError)
  ok(result->Result.mapError(why => !(why->String.includes(grant.bearer))) == Error(true))
  deepEqual(operations, ["upload"])
})

testAsync("grant transport errors never expose the proof", async () => {
  let (grant, _) = faked()
  let broken = {...grant, fetch: async (_, _) => JsError.throwWithMessage(grant.bearer)}
  let result = await Grant.deploy(broken, ~artifact, ~expected=7., ~candidate)
  ok(result == Error("grant upload did not answer"))
})

test("grant options require expected version and all four full candidate commits", () => {
  ok(Arguments.grant(args)->Result.isOk)
  ok(Arguments.grant(args->Array.slice(~start=0, ~end=-2))->Result.isError)
  ["-1", "1.5", "9007199254740991", "9007199254740992"]->Array.forEach(version => {
    let changed = args->Array.map(value => value)
    changed->Array.set(3, version)
    ok(Arguments.grant(changed)->Result.isError)
  })
  let changed = args->Array.map(value => value)
  changed->Array.set(5, String.repeat("A", 40))
  ok(Arguments.grant(changed)->Result.isError)
})

test("grant mode refuses secrets and binding before build or operator lookup", () => {
  [
    ["--secrets", "A"],
    ["--secrets", ""],
    ["--binding", "00000001"],
    ["--app", "00000001"],
    ["--network", "http"],
    ["--ingress", "binding"],
  ]->Array.forEach(flags => {
    ok(Arguments.grant([...args, ...flags])->Result.isError)
    let result = spawnSync(
      executable,
      ["src/main.res.mjs", ...args, ...flags],
      {
        "env": dict{"CONTROL_PRODUCTION_DEPLOY": "fake deployment proof"},
        "encoding": "utf8",
      },
    )
    deepEqual(result.status->Nullable.toOption, Some(2))
    ok(result.stderr->String.includes("grant deployment takes no policy or operator options"))
    ok(!(result.stderr->String.includes("fake deployment proof")))
    ok(!(result.stdout->String.includes("fake deployment proof")))
  })
})
