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

/** Whether another app may declare a scope, read by refusal as every store keeps it. */
let refusedScope = async (state: State.t, deployment: State.deployment, scope) =>
  switch await state.deploy({...deployment, ingress: [Mount({scope: scope})]}) {
  | () => None
  | exception Ingress.ScopeHeld(held) => Some(held)
  }

test(
  "a scope is held within an organization and given back by deploy, forget and retire",
  async () => {
    for i in 0 to stores->Array.length - 1 {
      let store = (stores->Array.getUnsafe(i))()
      let state = store.state(Sealing.ofKey(key))
      let first = await state.openOrganization("first", ~secret)
      let second = await state.openOrganization("second", ~secret)
      let binding = await state.openBinding(
        ~organization=first.id,
        ~secret,
        ~relayed=false,
        ~random=() => 16777218.,
      )
      let elsewhere = await state.openBinding(
        ~organization=second.id,
        ~secret,
        ~relayed=false,
        ~random=() => 16777219.,
      )
      await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
      let holder = await state.drawApp(~random=() => 16777220.)
      let other = await state.drawApp(~random=() => 16777221.)
      let abroad = await state.drawApp(~random=() => 16777222.)
      let deployment: State.deployment = {
        app: holder,
        binding,
        release: "aa",
        capacity: 0.,
        kind: Some(Function),
        ingress: [Mount({scope: "hello"})],
      }
      let another = {...deployment, app: other}
      await state.deploy(deployment)
      deepEqual(await refusedScope(state, another, "hello"), Some("hello"), ~message=store.name)
      deepEqual(await state.deployment(other), None, ~message=store.name)
      // Another organization's scopes are its own.
      await state.deploy({...deployment, app: abroad, binding: elsewhere})
      // Deploying again keeps a scope the app already holds.
      await state.deploy(deployment)
      deepEqual(await refusedScope(state, another, "hello"), Some("hello"), ~message=store.name)
      // A deploy declaring another scope gives the first back.
      await state.deploy({...deployment, ingress: [Mount({scope: "moved"})]})
      deepEqual(await refusedScope(state, another, "hello"), None, ~message=store.name)
      deepEqual(await refusedScope(state, deployment, "hello"), Some("hello"), ~message=store.name)
      await state.deploy({...another, ingress: []})
      await state.deploy(deployment)
      await state.retireApp(holder)
      deepEqual(await refusedScope(state, another, "hello"), None, ~message=store.name)
      // A forget gives back what an app that never ran declared.
      await state.deploy({...another, kind: None, capacity: 0.})
      ok(await state.forgetApp(other), ~message=store.name)
      let last = await state.drawApp(~random=() => 16777223.)
      deepEqual(
        await refusedScope(state, {...deployment, app: last}, "hello"),
        None,
        ~message=store.name,
      )
    }
  },
)

test("the gateway's view reads a mount by its organization and scope alone", async () => {
  let database = Sqlite.database()
  let state = State.ofDatabase(database, ~sealing=Sealing.ofKey(key))
  let reads = State.readsOfDatabase(database)
  let organization = (await state.openOrganization("first", ~secret)).id
  let binding = await state.openBinding(~organization, ~secret, ~relayed=false, ~random=() =>
    16777218.
  )
  await state.putRelease({hash: "aa", form: Modules, size: 3., kinds: None})
  let app = await state.drawApp(~random=() => 16777220.)
  let deployment: State.deployment = {
    app,
    binding,
    release: "aa",
    capacity: 0.,
    kind: Some(Function),
    ingress: [Mount({scope: "hello"}), Mount({scope: "hello"})],
  }
  await state.deploy(deployment)
  deepEqual(await reads.mount(~organization, ~scope="hello"), Some(app))
  deepEqual(await reads.mount(~organization=organization +. 1., ~scope="hello"), None)
  deepEqual(await reads.mount(~organization, ~scope="other"), None)
  await state.retireApp(app)
  deepEqual(await reads.mount(~organization, ~scope="hello"), None)
})
