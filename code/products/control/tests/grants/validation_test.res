open Node
open Grant_fixture

test("a Modules archive can restate the app's fixed ingress and function kind", async () => {
  let t = await make()
  let ingress = [C.AppIngress.Domain({domain: "control.test"})]
  let d = (await t.context.state.deployment(16777236.))->Option.getOrThrow
  await t.context.state.deploy({...d, ingress})
  let grant = await mint(t, ())
  let metadata = JSON.Object(
    dict{
      "main_module": String("worker.js"),
      "compatibility_date": String("2026-10-21"),
      "ingress": Array(ingress->Array.map(C.AppIngress.toJson)),
      "kinds": Array([String("function")]),
    },
  )
  let digest = await upload(t, grant, ~bytes=archive(~metadata, ()), ())
  deepEqual((await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason, None)
  deepEqual(
    t.seen->Array.getUnsafe(0)->Called.member("input")->Called.member("ingress"),
    JSON.Array(ingress->Array.map(C.AppIngress.toJson)),
  )
})

test(
  "upload refuses invalid archives, ingress, kinds, non Modules metadata and a mismatching digest",
  async () => {
    let t = await make()
    let grant = await mint(t, ())
    let invalid = [
      Web.utf8("not an archive"),
      archive(
        ~metadata=Object(
          dict{
            "main_module": String("worker.js"),
            "compatibility_date": String("2026-10-21"),
            "ingress": Array([C.AppIngress.toJson(Domain({domain: "other.test"}))]),
          },
        ),
        (),
      ),
      archive(
        ~metadata=Object(
          dict{
            "main_module": String("worker.js"),
            "compatibility_date": String("2026-10-21"),
            "kinds": Array([String("container")]),
          },
        ),
        (),
      ),
      archive(
        ~metadata=Object(
          dict{
            "main_module": String("worker.js"),
            "compatibility_date": String("2026-10-21"),
            "form": String("image"),
          },
        ),
        (),
      ),
    ]
    for i in 0 to invalid->Array.length - 1 {
      let artifact = invalid->Array.getUnsafe(i)
      deepEqual(
        (
          await call(t, grant.caller, Upload({artifact, digest: await Web.sha256(artifact)}))
        )->reason,
        Some("invalid"),
      )
    }
    deepEqual(
      (
        await call(
          t,
          grant.caller,
          Upload({artifact: archive(), digest: Uint8Array.fromLength(32)}),
        )
      )->reason,
      Some("hash_mismatch"),
    )
    deepEqual(t.held->Dict.keysToArray, [])
  },
)

test("upload refuses over 32 MiB and expiry or revocation before storing", async () => {
  let t = await make()
  let grant = await mint(t, ())
  let bytes = archive(~bytes=Uint8Array.fromLength(33554432), ())
  deepEqual(
    (
      await call(t, grant.caller, Upload({artifact: bytes, digest: await Web.sha256(bytes)}))
    )->reason,
    Some("too_large"),
  )
  let held = t.context.artifacts
  let changed = {
    ...t,
    context: {
      ...t.context,
      artifacts: {
        ...held,
        put: async (name, bytes) => {
          ignore(await Grant_store.revoke(t.context.store, grant.proof.grant))
          await held.put(name, bytes)
        },
      },
    },
  }
  deepEqual(
    (
      await call(
        changed,
        grant.caller,
        Upload({artifact: archive(), digest: await Web.sha256(archive())}),
      )
    )->reason,
    Some("denied"),
  )
  deepEqual(await count(t, "grant_staging"), 0)
})

test(
  "upload deploy and status refuse changed app binding organization and ingress policies",
  async () => {
    for i in 0 to 2 {
      let t = await make()
      let grant = await mint(t, ())
      let digest = await upload(t, grant, ())
      let d = (await t.context.state.deployment(16777236.))->Option.getOrThrow
      if i == 0 {
        ignore(
          await t.context.state.openBinding(
            ~organization=1.,
            ~secret=Uint8Array.fromLength(32),
            ~relayed=false,
            ~random=() => 16777227.,
          ),
        )
        await Grant_store.run(
          t.context.store,
          "UPDATE deployment SET binding = 16777227 WHERE app = 16777236",
          [],
        )
      } else if i == 1 {
        ignore(await t.context.state.openOrganization("other", ~secret=Uint8Array.fromLength(32)))
        await Grant_store.run(
          t.context.store,
          "UPDATE binding SET organization = 2 WHERE id = 16777226",
          [],
        )
      } else {
        await t.context.state.deploy({...d, ingress: [Domain({domain: "changed.test"})]})
      }
      deepEqual((await call(t, grant.caller, Status({})))->reason, Some("denied"))
      deepEqual(
        (await call(t, grant.caller, Upload({artifact: archive(), digest})))->reason,
        Some("denied"),
      )
      deepEqual(
        (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
        Some("denied"),
      )
    }
  },
)

test("deploy revalidates stored archive, candidate, digest and initialized resources", async () => {
  for i in 0 to 4 {
    let t = await make()
    let grant = await mint(t, ())
    let digest = await upload(t, grant, ())
    let key = Grant_context.stagingKey(grant.proof.grant, Envelope.Hex.encode(digest))
    let candidate = i == 2 ? {...candidate, cloud: "short"} : candidate
    if i == 0 {
      t.held->Dict.set(key, Web.utf8("broken"))
    }
    if i == 1 {
      t.held->Dict.set(key, archive(~bytes=Web.utf8("different"), ()))
    }
    if i == 3 {
      let d = (await t.context.state.deployment(16777236.))->Option.getOrThrow
      await t.context.state.deploy({...d, capacity: 0., kind: None})
    }
    if i == 4 {
      t.held->Dict.delete(key)
    }
    let expected = i == 3 ? "unbound" : i == 4 ? "not_found" : "invalid"
    deepEqual(
      (await call(t, grant.caller, Deploy({digest, expected: 0., candidate})))->reason,
      Some(expected),
    )
    deepEqual(t.seen->Array.length, 0)
  }
})

test("unknown selectors fail decoding before authorization in JSON and CBOR", async () => {
  let t = await make()
  let grant = await mint(t, ())
  let selectors = ["app", "binding", "organization", "ingress", "network", "secrets", "kind", "url"]
  for i in 0 to selectors->Array.length - 1 {
    let json = envelope(Deploy({digest: Uint8Array.fromLength(32), expected: 0., candidate}))
    json
    ->Called.member("input")
    ->JSON.Decode.object
    ->Option.getOrThrow
    ->Dict.set(selectors->Array.getUnsafe(i), JSON.Null)
    deepEqual((await callJson(t, grant.caller, json))->reason, Some("malformed"))
  }
  let json = envelope(Status({}))
  json->Called.member("input")->JSON.Decode.object->Option.getOrThrow->Dict.set("app", Number(21.))
  deepEqual((await callJson(t, grant.caller, json))->reason, Some("malformed"))
  let cbor = C.Interface.DeploymentGrants.toCbor({call: Status({}), capabilities: []})
  let altered = switch cbor {
  | Map(fields) =>
    Codec.Cbor.Map(
      fields->Array.map(((k, v)) =>
        k == Codec.Cbor.Integer(3n) ? (k, Codec.Cbor.Map([(Integer(99n), Null)])) : (k, v)
      ),
    )
  | Integer(_)
  | Bytes(_)
  | Text(_)
  | Array(_)
  | Tag(_)
  | Bool(_)
  | Null
  | Undefined
  | Simple(_)
  | Float(_) => cbor
  }
  ok(Grant_wire.fromCbor(altered)->Result.isError)
})
