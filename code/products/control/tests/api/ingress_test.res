open Node
open Called

let put = async (stood, name, ingress: option<array<Contracts.AppIngress.t>>) => {
  let (status, answer) = await called(
    stood,
    Operator,
    releases(Put({form: Modules, artifact: Web.utf8(name), ?ingress})),
  )
  (
    status,
    answer,
    answer->data->member("hash")->JSON.Decode.string->Option.flatMap(Envelope.Hex.decode),
  )
}

test("put refuses malformed domains before keeping an artifact", async () => {
  let bad = [
    "192.0.2.1",
    "*." ++ String.repeat("a.", 121) ++ "example.org",
    "EXAMPLE.com",
    "https://example.com",
    "example.com:443",
    "*.*.example.org",
    "a.*.example.org",
    "example..com",
    "-a.example.com",
    "a-.example.com",
    "example.com/",
    "example.com.",
    "",
    "*.example.com/path",
    "a_1.example.com",
    String.repeat("a", 64) ++ ".example.com",
    String.repeat("a.", 125) ++ "example.com",
  ]
  for i in 0 to bad->Array.length - 1 {
    let stood = stand()
    let domain = bad->Array.getUnsafe(i)
    let ingress: array<Contracts.AppIngress.t> = [Domain({domain: domain})]
    let (status, answer, _) = await put(stood, "invalid", Some(ingress))
    deepEqual(
      (status, answer->reason, stood.artifacts->Dict.keysToArray),
      (400, Some("invalid"), []),
      ~message=domain,
    )
  }
})

test(
  "deploy carries all ingress to the driver and refuses a domain held by another app",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (_, state) = states->Array.getUnsafe(i)
      let stood = stand()
      let stood = {...stood, parts: {...stood.parts, state}}
      let (binding, _) = await opened(stood)
      let ingress: array<Contracts.AppIngress.t> = [
        Contracts.AppIngress.Domain({domain: "example.com"}),
        Contracts.AppIngress.Domain({domain: "*.example.org"}),
        Mount({scope: "hello"}),
        Binding,
      ]
      let (status, _, hash) = await put(stood, "declared", Some(ingress))
      deepEqual(status, 200)
      let release = hash->Option.getOrThrow
      let (status, answer) = await called(stood, Operator, releases(Deploy({binding, release})))
      let app = answer->ranAs->Option.getOrThrow
      deepEqual((status, await state.domain("example.com")), (200, Some(app)))
      deepEqual(stood.host.deployed.contents->Option.flatMap(d => d.ingress), Some(ingress))
      let before = stood.host.deployed.contents
      let (status, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
      deepEqual((status, refused->reason), (400, Some("conflict")))
      ok(
        refused
        ->member("message")
        ->JSON.Decode.string
        ->Option.mapOr(false, m =>
          m->String.includes("is held by another app") &&
            (m->String.includes("example.com") || m->String.includes("*.example.org"))
        ),
      )
      deepEqual(
        (await state.domain("example.com"), stood.host.deployed.contents),
        (Some(app), before),
      )
      let (_, _, newHash) = await put(
        stood,
        "replacement",
        Some([Contracts.AppIngress.Domain({domain: "example.net"})]),
      )
      deepEqual(
        (
          await called(
            stood,
            Operator,
            releases(Deploy({app, binding, release: newHash->Option.getOrThrow})),
          )
        )->(((status, _)) => status),
        200,
      )
      deepEqual(
        (await state.domain("example.com"), await state.domain("example.net")),
        (None, Some(app)),
      )
      deepEqual(
        (await called(stood, Operator, releases(Retire({app: app}))))->(((status, _)) => status),
        200,
      )
      deepEqual(await state.domain("example.net"), None)
    }
  },
)

test("generated ingress is read back through JSON and CBOR at the release field", async () => {
  let ingress: array<Contracts.AppIngress.t> = [
    Domain({domain: "example.com"}),
    Domain({domain: "*.example.org"}),
    Mount({scope: "hello"}),
    Binding,
  ]
  let release: Contracts.ReleasePut.t = {form: Modules, artifact, ingress}
  let json = Contracts.ReleasePut.toJson(release)
  deepEqual(Contracts.ReleasePut.fromJson(json)->Result.map(Contracts.ReleasePut.toJson), Ok(json))
  deepEqual(
    Contracts.ReleasePut.fromCbor(Contracts.ReleasePut.toCbor(release))->Result.map(
      Contracts.ReleasePut.toJson,
    ),
    Ok(json),
  )
})
