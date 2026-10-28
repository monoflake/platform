/***
 * The API held to RFC emgxf, a release run as the first of its kinds its binding offers, a
 * function deployed into no container, and one sharing no kind beyond its host.
 */
open Node
open Called

/** A release put with the kinds it declares, its artifact its own, and its hash in hex. */
let putKinds = async (stood, text, kinds) => {
  let (_, put) = await called(
    stood,
    Operator,
    releases(Put({form: Modules, artifact: Web.utf8(text), ?kinds})),
  )
  put->data->member("hash")->JSON.Decode.string->Option.getOr("")
}

let bytesOf = hex => Envelope.Hex.decode(hex)->Option.getOr(Uint8Array.fromLength(0))

/** A control whose state counts the apps it draws and the deployments it writes. */
let watched = stood => {
  let (draws, writes) = (ref(0), ref(0))
  let state = stood.parts.state
  let counted = {
    ...state,
    drawApp: (~random) => {
      draws := draws.contents + 1
      state.drawApp(~random)
    },
    deploy: d => {
      writes := writes.contents + 1
      state.deploy(d)
    },
  }
  ({...stood, parts: {...stood.parts, state: counted}}, draws, writes)
}

test(
  "a modules release with no kinds on a machine binding asks the list and deploy it asked before",
  async () => {
    let described = [Some([Contracts.ManagementKind.Function, Container, Object, Volume]), None]
    for i in 0 to described->Array.length - 1 {
      let kinds = described->Array.getUnsafe(i)
      let stood = stand()
      stood.host.kinds := kinds
      let (binding, hash) = await opened(stood)
      let release = bytesOf(hash)
      let (status, answer) = await called(stood, Operator, releases(Deploy({binding, release})))
      let app = answer->ranAs->Option.getOr(0.)
      // The list and the deploy the control sent before kinds were matched, emgxf.
      let credentials =
        stood.host.applied.contents->Option.mapOr([], l =>
          l.items->Array.flatMap(i => i.credentials)
        )
      deepEqual(
        stood.host.applied.contents->Option.map(l =>
          JSON.stringify(Contracts.ManagementApply.toJson(l))
        ),
        Some(
          JSON.stringify(
            Contracts.ManagementApply.toJson({
              generation: 1.,
              items: [{id: 1., capacity: Deploying.capacity, credentials}],
            }),
          ),
        ),
      )
      deepEqual(credentials->Array.map(TypedArray.length), [32])
      deepEqual(
        stood.host.deployed.contents->Option.map(d =>
          JSON.stringify(Contracts.DeploymentDeploy.toJson(d))
        ),
        Some(
          JSON.stringify(
            Contracts.DeploymentDeploy.toJson({
              runs: App({id: app}),
              version: release,
              form: Modules,
              isolation: [Isolate],
              artifact: {address: `https://control.test/artifacts/${hash}`, hash: release},
              footing: "https://footing.invalid",
              secrets: dict{},
              network: [],
              into: 1.,
            }),
          ),
        ),
      )
      deepEqual(
        (status, stood.host.seen->Array.map(s => Web.parts(s.url)->Web.pathname)),
        (
          200,
          [
            "/management/describe",
            "/management/apply",
            "/management/describe",
            "/deployments/deploy",
          ],
        ),
      )
      deepEqual(
        (await stood.parts.state.deployment(app))->Option.map(d => (
          d.app,
          d.binding,
          d.release,
          d.capacity,
          d.kind,
          d.ingress,
        )),
        Some((app, binding, hash, 1., Some(Contracts.DeploymentKind.Function), None)),
      )
    }
  },
)

test(
  "a function on a binding offering no container is deployed into none, and has run",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let stood = stand()
      let stood = {...stood, parts: {...stood.parts, state}}
      stood.host.kinds := Some([Function, Object])
      let (binding, hash) = await opened(stood)
      let (status, answer) = await called(
        stood,
        Operator,
        releases(Deploy({binding, release: bytesOf(hash)})),
      )
      let app = answer->ranAs->Option.getOr(0.)
      deepEqual(
        (
          status,
          stood.host.seen->Array.map(s => Web.parts(s.url)->Web.pathname),
          stood.host.applied.contents,
          stood.host.deployed.contents->Option.map(d => d.into),
          (await state.deployment(app))->Option.map(d => (
            d.app,
            d.binding,
            d.release,
            d.capacity,
            d.kind,
            d.ingress,
          )),
        ),
        (
          200,
          ["/management/describe", "/deployments/deploy"],
          None,
          Some(None),
          Some((app, binding, hash, 0., Some(Contracts.DeploymentKind.Function), None)),
        ),
        ~message=name,
      )
      deepEqual(
        (await called(stood, Operator, releases(Forget({app: app}))))->refusal,
        (Some("deployed"), `app ${Ids.text(app)} has run, so it is removed by retire`),
        ~message=name,
      )
      let seen = stood.host.seen->Array.length
      let (status, _) = await called(stood, Operator, releases(Retire({app: app})))
      deepEqual(
        (status, askedSince(stood, seen), await state.deployment(app), await state.hasApp(app)),
        (200, ["/deployments/stop", "/deployments/delete"], None, false),
        ~message=name,
      )
    }
  },
)

test(
  "a release sharing no kind with its binding is beyond its host, and draws nothing",
  async () => {
    let (stood, draws, writes) = watched(stand())
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "a function", Some([Function]))
    stood.host.kinds := Some([Container, Object])
    let (status, answer) = await called(
      stood,
      Operator,
      releases(Deploy({binding, release: bytesOf(hash)})),
    )
    deepEqual(
      (
        (status, answer)->refusal,
        draws.contents,
        writes.contents,
        stood.host.seen->Array.map(s => Web.parts(s.url)->Web.pathname),
      ),
      (
        (
          Some("beyond_host"),
          `release ${hash} runs as function, and binding ${Ids.text(
              binding,
            )} offers container, object`,
        ),
        0,
        0,
        ["/management/describe"],
      ),
    )
    deepEqual(status, 400)
  },
)

test("a redeploy of a release its binding no longer runs changes nothing it holds", async () => {
  let stood = stand()
  let (binding, hash) = await opened(stood)
  let release = bytesOf(hash)
  let (_, first) = await called(stood, Operator, releases(Deploy({binding, release})))
  let app = first->ranAs->Option.getOr(0.)
  let held = await stood.parts.state.deployment(app)
  stood.host.kinds := Some([Container])
  let (stood, draws, writes) = watched(stood)
  let again = await called(stood, Operator, releases(Deploy({binding, app, release})))
  deepEqual(
    (again->refusal, draws.contents, writes.contents),
    (
      (
        Some("beyond_host"),
        `release ${hash} runs as function, and binding ${Ids.text(binding)} offers container`,
      ),
      0,
      0,
    ),
  )
  deepEqual(await stood.parts.state.deployment(app), held)
})

test(
  "a release declaring instance alone is beyond every binding, one offering it too",
  async () => {
    let stood = stand()
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "an instance", Some([Instance]))
    let deployed = async kinds => {
      stood.host.kinds := kinds
      let answer = await called(
        stood,
        Operator,
        releases(Deploy({binding, release: bytesOf(hash)})),
      )
      answer->refusal
    }
    let named = Ids.text(binding)
    deepEqual(
      (await deployed(Some([Function, Instance, Container])), await deployed(None)),
      (
        (
          Some("beyond_host"),
          `release ${hash} runs as instance, which this control deploys onto no binding yet`,
        ),
        (
          Some("beyond_host"),
          `release ${hash} runs as instance, and binding ${named} offers function, container`,
        ),
      ),
    )
    deepEqual(stood.host.deployed.contents, None)
  },
)

test(
  "a release declaring an empty list of kinds is beyond every binding, and draws nothing",
  async () => {
    let (stood, draws, writes) = watched(stand())
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "no kinds", Some([]))
    let (status, answer) = await called(
      stood,
      Operator,
      releases(Deploy({binding, release: bytesOf(hash)})),
    )
    deepEqual(
      ((status, answer)->refusal, status, draws.contents, writes.contents),
      ((Some("beyond_host"), `release ${hash} declares no kind it runs as`), 400, 0, 0),
    )
  },
)

test(
  "the first of a release's kinds its binding offers is chosen, in the release's order",
  async () => {
    let stood = stand()
    stood.host.kinds := Some([Function, Container])
    let (binding, _) = await opened(stood)
    let hash = await putKinds(stood, "a container first", Some([Container, Function]))
    let (status, answer) = await called(
      stood,
      Operator,
      releases(Deploy({binding, release: bytesOf(hash)})),
    )
    let app = answer->ranAs->Option.getOr(0.)
    deepEqual(
      (
        status,
        (await stood.parts.state.deployment(app))->Option.map(d => (
          d.app,
          d.binding,
          d.release,
          d.capacity,
          d.kind,
          d.ingress,
        )),
        stood.host.deployed.contents->Option.map(d => d.into),
      ),
      (
        200,
        Some((app, binding, hash, 1., Some(Contracts.DeploymentKind.Container), None)),
        Some(Some(1.)),
      ),
    )
  },
)

test(
  "a release keeps the kinds it was put with, a second put of its hash changing nothing",
  async () => {
    let states = kept()
    for i in 0 to states->Array.length - 1 {
      let (name, state) = states->Array.getUnsafe(i)
      let stood = stand()
      let stood = {...stood, parts: {...stood.parts, state}}
      let ordered = await putKinds(stood, "ordered", Some([Container, Function]))
      let again = await putKinds(stood, "ordered", None)
      let empty = await putKinds(stood, "empty", Some([]))
      let none = await putKinds(stood, "none", None)
      let kindsOf = async hash => (await state.release(hash))->Option.map(r => r.kinds)
      deepEqual(
        (again == ordered, await kindsOf(ordered), await kindsOf(empty), await kindsOf(none)),
        (
          true,
          Some(Some([Contracts.DeploymentKind.Container, Function])),
          Some(Some([])),
          Some(None),
        ),
        ~message=name,
      )
    }
  },
)
