/***
 * Retire held over each state the API keeps, an app that ran stopped and deleted by its driver
 * before its rows are removed, and every other app or caller refused.
 */
open Node
open Called

/** A control standing over a state, an app that ran on it and one drawn that never ran. */
let ranAndNever = async state => {
  let stood = stand()
  let stood = {...stood, parts: {...stood.parts, state}}
  let (binding, hash) = await opened(stood)
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  stood.host.cut := Some("/management/apply")
  let (_, refused) = await called(stood, Operator, releases(Deploy({binding, release})))
  stood.host.cut := None
  let never = refused->named->Option.getOr(0.)
  let (_, deployed) = await called(stood, Operator, releases(Deploy({binding, release})))
  (stood, binding, release, deployed->ranAs->Option.getOr(0.), never)
}

test("retire stops then deletes an app that ran, and only then removes its rows", async () => {
  let states = kept()
  for i in 0 to states->Array.length - 1 {
    let (name, state) = states->Array.getUnsafe(i)
    let (stood, binding, release, ran, _) = await ranAndNever(state)
    let seen = stood.host.seen->Array.length
    let (status, retired) = await called(stood, Operator, releases(Retire({app: ran})))
    deepEqual(
      (status, retired->data),
      (200, JSON.parseOrThrow(`{"app": ${Float.toString(ran)}}`)),
      ~message=name,
    )
    deepEqual(askedSince(stood, seen), ["/deployments/stop", "/deployments/delete"], ~message=name)
    deepEqual((await state.deployment(ran), await state.hasApp(ran)), (None, false), ~message=name)
    // A deploy naming it afterwards finds no app and asks no driver.
    let seen = stood.host.seen->Array.length
    let again = await called(stood, Operator, releases(Deploy({binding, app: ran, release})))
    deepEqual(
      (again->refusal, stood.host.seen->Array.length),
      ((Some("not_found"), `no app ${Ids.text(ran)} is deployed`), seen),
      ~message=name,
    )
    deepEqual(
      (await called(stood, Operator, releases(Retire({app: ran}))))->refusal,
      (Some("not_found"), `no app ${Ids.text(ran)} is held`),
      ~message=name,
    )
  }
})

test(
  "retire refuses an app that never ran, an id not held, and every caller but the operator",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let (stood, binding, _, ran, never) = await ranAndNever(state)
      let seen = stood.host.seen->Array.length
      let bare = await state.drawApp(~random=() => 4275878551.)
      let retire = app => releases(Retire({app: app}))
      let refusals = [
        await called(stood, Operator, retire(never)),
        await called(stood, Operator, retire(bare)),
        await called(stood, Operator, retire(4275878552.)),
        await called(stood, Host(binding), retire(ran)),
        await called(stood, Organization(1.), retire(ran)),
      ]
      deepEqual(
        refusals->Array.map(refusal),
        [
          (Some("not_deployed"), `app ${Ids.text(never)} never ran, so it is removed by forget`),
          (Some("not_deployed"), "app fedcba97 never ran, so it is removed by forget"),
          (Some("not_found"), "no app fedcba98 is held"),
          (Some("denied"), "The call carries no credential, or one that does not allow it"),
          (Some("denied"), "The call carries no credential, or one that does not allow it"),
        ],
        ~message=name,
      )
      // Nothing is asked of the host, and every app is still held.
      deepEqual(stood.host.seen->Array.length, seen, ~message=name)
      deepEqual(
        (
          (await state.deployment(never))->Option.map(d => d.capacity),
          await state.hasApp(bare),
          (await state.deployment(ran))->Option.isSome,
        ),
        (Some(0.), true, true),
        ~message=name,
      )
    }
  },
)

test(
  "retire of an app whose driver is not reached is unreachable and removes nothing",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let (stood, _, _, ran, _) = await ranAndNever(state)
      stood.host.gone := true
      let (status, answer) = await called(stood, Operator, releases(Retire({app: ran})))
      deepEqual((status, answer->reason), (503, Some("unreachable")), ~message=name)
      deepEqual(
        ((await state.deployment(ran))->Option.isSome, await state.hasApp(ran)),
        (true, true),
        ~message=name,
      )
      // Retired once the driver answers again.
      stood.host.gone := false
      let (status, _) = await called(stood, Operator, releases(Retire({app: ran})))
      deepEqual((status, await state.deployment(ran)), (200, None), ~message=name)
    }
  },
)

test("retire takes a driver answering not_found as the deployment gone already", async () => {
  let states = kept()
  for i in 0 to states->Array.length - 1 {
    let (name, state) = states->Array.getUnsafe(i)
    let (stood, _, _, ran, _) = await ranAndNever(state)
    stood.host.lost := true
    let seen = stood.host.seen->Array.length
    let (status, _) = await called(stood, Operator, releases(Retire({app: ran})))
    deepEqual(
      (status, askedSince(stood, seen)),
      (200, ["/deployments/stop", "/deployments/delete"]),
      ~message=name,
    )
    deepEqual((await state.deployment(ran), await state.hasApp(ran)), (None, false), ~message=name)
  }
})

test("retire passes on a delete the driver refused, and removes nothing", async () => {
  let stood = stand()
  // A driver whose stop leaves the deployment running, as one past its grace would.
  let reach = stood.host.reach
  let stubborn: Reach.t = {
    ...reach,
    fetch: async request =>
      Web.parts(request->Web.url)->Web.pathname == "/deployments/stop"
        ? Host.success(
            Contracts.DeploymentDescribed.toJson({
              runs: App({id: 1.}),
              version: Uint8Array.fromLength(32),
              state: Making,
            }),
          )
        : await reach.fetch(request),
  }
  let stood = {...stood, parts: {...stood.parts, reach: stubborn}}
  let (binding, hash) = await opened(stood)
  let release = Envelope.Hex.decode(hash)->Option.getOr(Uint8Array.fromLength(0))
  let (_, deployed) = await called(stood, Operator, releases(Deploy({binding, release})))
  let ran = deployed->ranAs->Option.getOr(0.)
  let (status, answer) = await called(stood, Operator, releases(Retire({app: ran})))
  deepEqual(
    (status, answer->member("failure")->JSON.Decode.string, (status, answer)->refusal),
    (400, Some("rejected"), (Some("still_running"), "it runs")),
  )
  ok((await stood.parts.state.deployment(ran))->Option.isSome)
})

test("retire of an app whose binding is not held is unreachable and removes nothing", async () => {
  // D1's foreign key keeps every deployment's binding, so only memory and objects can lose one.
  let states = kept()->Array.filter(((name, _)) => name != "D1")
  for i in 0 to states->Array.length - 1 {
    let (name, state) = states->Array.getUnsafe(i)
    let stood = stand()
    let stood = {...stood, parts: {...stood.parts, state}}
    let app = await state.drawApp(~random=() => 4275878551.)
    await state.deploy({app, binding: 4275878552., release: "aa", capacity: 1., kind: None})
    let (status, answer) = await called(stood, Operator, releases(Retire({app: app})))
    deepEqual(
      (status, answer->member("failure")->JSON.Decode.string, (status, answer)->refusal),
      (
        503,
        Some("unavailable"),
        (
          Some("unreachable"),
          "app fedcba97 runs on binding fedcba98, which is not held, so no driver is asked",
        ),
      ),
      ~message=name,
    )
    deepEqual(
      (stood.host.seen, (await state.deployment(app))->Option.isSome, await state.hasApp(app)),
      ([], true, true),
      ~message=name,
    )
  }
})
