open Stored
open Node
module Contracts = Envelope.Contracts

let declared: array<Contracts.AppIngress.t> = [
  Domain({domain: "example.com"}),
  Domain({domain: "*.example.org"}),
  Mount({scope: "hello"}),
  Binding,
]

test("ingress is kept with the release and deployment and domains follow the app", async () => {
  for i in 0 to stores->Array.length - 1 {
    let store = (stores->Array.getUnsafe(i))()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let binding = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=() => 16777218.,
    )
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None, ingress: declared})
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    deepEqual(
      (await state.release("aa"))->Option.flatMap(r => r.ingress),
      Some(declared),
      ~message=store.name,
    )
    let app = await state.drawApp(~random=() => 16777220.)
    let deployment: State.deployment = {
      app,
      binding,
      release: "aa",
      capacity: 0.,
      kind: None,
      ingress: declared,
    }
    await state.deploy(deployment)
    deepEqual((await state.deployment(app))->Option.flatMap(d => d.ingress), Some(declared))
    deepEqual(
      (await state.domain("example.com"), await state.domain("*.example.org")),
      (Some(app), Some(app)),
    )
    await state.deploy({...deployment, ingress: [Domain({domain: "example.net"})]})
    deepEqual(
      (
        await state.domain("example.com"),
        await state.domain("*.example.org"),
        await state.domain("example.net"),
      ),
      (None, None, Some(app)),
    )
    await state.deploy({...deployment, ingress: []})
    deepEqual(await state.domain("example.net"), None)
    await state.deploy(deployment)
    ok(await state.forgetApp(app), ~message=store.name)
    deepEqual(await state.domain("example.com"), None)
    ignore(await state.drawApp(~random=() => app))
    await state.deploy({...deployment, kind: Some(Function)})
    await state.retireApp(app)
    deepEqual(
      (await state.domain("example.com"), await state.domain("*.example.org")),
      (None, None),
    )
  }
})

test("a conflicting domain rolls back replacement and leaves both deployments intact", async () => {
  for i in 0 to stores->Array.length - 1 {
    let store = (stores->Array.getUnsafe(i))()
    let state = store.state(Sealing.ofKey(key))
    let organization = await state.openOrganization("first", ~secret)
    let binding = await state.openBinding(
      ~organization=organization.id,
      ~secret,
      ~relayed=false,
      ~random=() => 16777218.,
    )
    await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
    let first = await state.drawApp(~random=() => 16777220.)
    let second = await state.drawApp(~random=() => 16777221.)
    let deployment: State.deployment = {
      app: first,
      binding,
      release: "aa",
      capacity: 0.,
      kind: Some(Function),
      ingress: [Domain({domain: "example.com"})],
    }
    let other = {...deployment, app: second, ingress: [Domain({domain: "example.net"})]}
    await state.deploy(deployment)
    await state.deploy(other)
    let refused = switch await state.deploy({
      ...other,
      ingress: [Domain({domain: "free.example.org"}), Domain({domain: "example.com"})],
    }) {
    | () => None
    | exception State.DomainHeld(domain) => Some(domain)
    }
    deepEqual(refused, Some("example.com"), ~message=store.name)
    deepEqual(
      (
        await state.domain("example.com"),
        await state.domain("example.net"),
        await state.domain("free.example.org"),
      ),
      (Some(first), Some(second), None),
    )
    deepEqual(await state.deployment(second), Some(other))
    await state.retireApp(first)
    await state.deploy({...other, ingress: [Domain({domain: "example.com"})]})
    deepEqual(await state.domain("example.com"), Some(second))
  }
})
