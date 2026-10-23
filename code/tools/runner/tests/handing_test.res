/***
 * `Handing` held to the host component's call, a send to an address a deployment was answered
 * running at described first, posted while it runs and refused once it is stopped.
 */
open Node

let runs = `{"name": "app", "id": 1}`

/** A deployment in memory, running at an address until stopped, each describe's form kept. */
let deployment = () => {
  let stopped = ref(false)
  let forms = []
  let call = async (~interface as _, ~operation, ~input as _, ~form, ~as_ as _) => {
    if operation == "describe" {
      forms->Array.push(form)
    }
    let state = stopped.contents
      ? `{"name": "stopped"}`
      : `{"name": "running", "address": "http://10.0.0.2:8080", "runtime": "workerd", "isolation": ["isolate"]}`
    Ok(
      Run.Answered(
        JSON.parseOrThrow(
          `{"runs": ${runs}, "version": "${String.repeat("ab", 32)}", "state": ${state}}`,
        ),
      ),
    )
  }
  let target: Run.target = {
    call,
    send: async (~to as _, ~export as _, ~key as _, ~body as _, ~form as _) => Error("direct"),
    given: async (~interface as _, ~form as _, _) => Ok(),
    lose: async _ => Ok(),
    bound: _ => None,
    fixture: _ => Error("none"),
    signed: (_, _) => Error("none"),
    now: () => 0.,
    wait: async _ => (),
  }
  let posted = []
  let post = async (url, request: Host.Handed.request): result<Host.Handed.response, _> => {
    posted->Array.push((url, Web.text(request.body)))
    Ok({status: 200, contentType: Some("application/json"), body: request.body})
  }
  (Handing.target(target, ~post), stopped, forms, posted)
}

let describe = (target: Run.target) =>
  target.call(
    ~interface="deployments",
    ~operation="describe",
    ~input=JSON.parseOrThrow(`{"runs": ${runs}}`),
    ~form=Cbor,
    ~as_=None,
  )

let body = Some(JSON.parseOrThrow(`{"text": "hello"}`))

test("a deployments answer names the deployment running at its address", () => {
  deepEqual(
    Handing.running(
      JSON.parseOrThrow(`{"runs": ${runs}, "state": {"name": "running", "address": "a:1"}}`),
    ),
    Some(("a:1", JSON.parseOrThrow(runs))),
  )
  deepEqual(
    Handing.running(JSON.parseOrThrow(`{"runs": ${runs}, "state": {"name": "stopped"}}`)),
    None,
  )
})

testAsync("a send is described in its form first, then posted to its export and key", async () => {
  let (target, _, forms, posted) = deployment()
  ignore(await describe(target))
  let sent = await target.send(
    ~to="http://10.0.0.2:8080",
    ~export="echo",
    ~key=None,
    ~body,
    ~form=Json,
  )
  deepEqual(sent, Ok(Run.Answered(JSON.parseOrThrow(`{"text": "hello"}`))))
  ignore(
    await target.send(
      ~to="http://10.0.0.2:8080",
      ~export="increment",
      ~key=Some("a"),
      ~body,
      ~form=Cbor,
    ),
  )
  deepEqual(forms, [Run.Cbor, Json, Cbor])
  deepEqual(
    posted,
    [
      ("http://10.0.0.2:8080/echo", `{"text":"hello"}`),
      ("http://10.0.0.2:8080/a/increment", `{"text":"hello"}`),
    ],
  )
})

testAsync(
  "a send to a deployment stopped is refused as stopped, and nothing is posted",
  async () => {
    let (target, stopped, _, posted) = deployment()
    ignore(await describe(target))
    stopped := true
    deepEqual(
      await target.send(~to="http://10.0.0.2:8080", ~export="echo", ~key=None, ~body, ~form=Json),
      Ok(
        Run.Failed({
          failure: "unavailable",
          reason: "stopped",
          message: "What was called is stopped",
        }),
      ),
    )
    deepEqual(posted, [])
  },
)

testAsync("a send to an address no deployment was answered running at is no answer", async () => {
  let (target, _, _, posted) = deployment()
  ok(
    (
      await target.send(~to="http://10.0.0.9:1", ~export="echo", ~key=None, ~body, ~form=Json)
    )->Result.isError,
  )
  deepEqual(posted, [])
})
