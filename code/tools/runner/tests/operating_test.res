/***
 * `Operating` and `Reaching` held to RFC 8j7b0, a call as the operator on the operator's operations
 * alone, the organization the run is told, and the network never probed.
 */
open Node

/** A target keeping each call's operation, `as` and bearer. */
let kept = () => {
  let seen = []
  let target: Run.target = {
    call: async (~interface as _, ~operation, ~input as _, ~form as _, ~as_, ~bearer) => {
      seen->Array.push((operation, as_, bearer))
      Ok(Run.Answered(JSON.parseOrThrow(`{"binding": 3, "secret": "c2VjcmV0"}`)))
    },
    send: async (~to as _, ~export as _, ~key as _, ~body as _, ~form as _) => Error("none"),
    given: async (~interface as _, ~form as _, _) => Ok(),
    lose: async _ => Ok(),
    bound: _ => None,
    fixture: _ => Error("none"),
    signed: (_, _) => Error("none"),
    now: () => 0.,
    wait: async _ => (),
    network: false,
    tunnel: false,
    captured: dict{},
  }
  (target, seen)
}

let called = (target: Run.target, ~operation, ~as_, ~bearer) =>
  target.call(~interface="bindings", ~operation, ~input=JSON.Null, ~form=Json, ~as_, ~bearer)

test("the operator's operations are those whose callers in contracts.json name it", () => {
  let contracts = JSON.parseOrThrow(`{"interfaces": {
    "bindings": {"operations": [
      {"name": "open", "callers": ["operator"]},
      {"name": "bind", "callers": ["host"]}
    ]},
    "releases": {"operations": [{"name": "put", "callers": ["host", "operator"]}, {"name": "x"}]}
  }}`)
  deepEqual(Operating.operated(contracts), ["bindings/open", "releases/put"])
  let model = JSON.parseOrThrow(readFileSync(fromRoot("model/contracts.json")))
  ok(Operating.operated(model)->Array.includes("bindings/open"), ~message="the model's own")
  ok(!(Operating.operated(model)->Array.includes("bindings/bind")), ~message="bind is the host's")
})

testAsync(
  "a call as the operator carries its credential on the operator's operations alone",
  async () => {
    let (target, seen) = kept()
    let operated = Operating.target(
      target,
      ~credential=Some("operator-secret"),
      ~operated=["bindings/open"],
    )
    ignore(await called(operated, ~operation="open", ~as_=Some("operator"), ~bearer=None))
    ignore(await called(operated, ~operation="bind", ~as_=Some("compute"), ~bearer=None))
    ignore(await called(operated, ~operation="bind", ~as_=None, ~bearer=Some("4.c2VjcmV0")))
    let refused = await called(operated, ~operation="bind", ~as_=Some("operator"), ~bearer=None)
    deepEqual(
      seen,
      [
        ("open", None, Some("operator-secret")),
        ("bind", Some("compute"), None),
        ("bind", None, Some("4.c2VjcmV0")),
      ],
    )
    deepEqual(
      refused,
      Error("bindings bind is no operation of the operator's, by the model's callers"),
    )
    let unheld = Operating.target(target, ~credential=None, ~operated=["bindings/open"])
    deepEqual(
      await called(unheld, ~operation="open", ~as_=Some("operator"), ~bearer=None),
      Error("a call as the operator, yet no CONTROL_OPERATOR is given"),
    )
    deepEqual(seen->Array.length, 3)
  },
)

test("a case uses the run's organization wherever a step writes it", () => {
  let cases = switch Sample.read(`{"interface": "bindings", "cases": [
    {"description": "input", "steps": [{"call": "open", "input": {"organization": {"$use": "organization"}}, "expect": {"output": {}}}]},
    {"description": "expected", "steps": [{"call": "open", "input": {}, "expect": {"output": {"a": [{"$use": "organization"}]}}}]},
    {"description": "neither", "steps": [{"call": "open", "input": {"organization": 4294967295}, "expect": {"output": {"$use": "opened"}}}]}
  ]}`) {
  | Ok(file) => file.cases
  | Error(why) => JsError.throwWithMessage(why)
  }
  deepEqual(cases->Array.map(Operating.usedBy), [true, true, false])
})

test("a run is told its organization, and refused naming the cases using it where it is not", () =>
  deepEqual(
    [
      Operating.captured(Some("12"), ~using=["a.json: one"]),
      Operating.captured(None, ~using=[]),
      Operating.captured(None, ~using=["a.json: one", "a.json: two"]),
      Operating.captured(Some("012"), ~using=[]),
      Operating.captured(Some("4294967296"), ~using=[]),
    ],
    [
      Ok(dict{"organization": JSON.Number(12.)}),
      Ok(dict{}),
      Error(
        "--organization is required by the cases using the run's organization: a.json: one; a.json: two",
      ),
      Error("--organization 012, no id of an organization"),
      Error("--organization 4294967296, no id of an organization"),
    ],
  )
)

test("the network is reached only where --network yes says so, and never probed", () =>
  deepEqual(
    [
      Reaching.reaches(Some("yes")),
      Reaching.reaches(Some("no")),
      Reaching.reaches(None),
      Reaching.reaches(Some("maybe")),
    ],
    [Ok(true), Ok(false), Ok(false), Error("--network maybe, neither yes nor no")],
  )
)

test(
  "a tunnel bind is run only where --tunnel yes says so, against a control on the loopback",
  () =>
    deepEqual(
      [
        Reaching.tunnels(Some("yes"), ~base="http://localhost:8787"),
        Reaching.tunnels(Some("yes"), ~base="http://127.0.0.1:8787/"),
        Reaching.tunnels(Some("yes"), ~base="http://[::1]:8787"),
        Reaching.tunnels(Some("yes"), ~base="http://control.localhost"),
        Reaching.tunnels(Some("no"), ~base="https://control.example.com"),
        Reaching.tunnels(None, ~base="https://control.example.com"),
        Reaching.tunnels(Some("yes"), ~base="https://control.example.com"),
        Reaching.tunnels(Some("yes"), ~base="http://192.0.2.1:8787"),
        Reaching.tunnels(Some("yes"), ~base="http://127.0.0.1.example.com"),
        Reaching.tunnels(Some("yes"), ~base="not a url"),
        Reaching.tunnels(Some("maybe"), ~base="http://localhost:8787"),
      ]->Array.map(r =>
        switch r {
        | Ok(run) => run ? "run" : "skipped"
        | Error(why) => why->String.startsWith("--tunnel yes against") ? "refused" : why
        }
      ),
      [
        "run",
        "run",
        "run",
        "run",
        "skipped",
        "skipped",
        "refused",
        "refused",
        "refused",
        "refused",
        "--tunnel maybe, neither yes nor no",
      ],
    ),
)
