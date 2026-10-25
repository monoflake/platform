/***
 * `Control` held to RFC rxmd9, a target naming a control read, and the release put, deployed,
 * described and asked through the gateway against a fetch faked.
 */
open Node
module Contracts = Envelope.Contracts

let hash = Uint8Array.fromArray(Array.make(~length=32, 0xab))

type sent = {url: string, init: Web.init}

/** A control faked, each call kept and answered by its path. */
let faked = answers => {
  let sent = []
  let control: Control.t = {
    origin: "http://localhost:8787",
    operator: "the secret",
    fetch: async (url, init) => {
      sent->Array.push({url, init})
      let path = url->String.replace("http://localhost:8787", "")
      switch answers->Dict.get(path) {
      | Some((status, body)) => response(body, {"status": status})
      | None => JsError.throwWithMessage("connection refused")
      }
    },
  }
  (control, sent)
}

let described = `{"status": "success", "data": {"runs": {"name": "app", "id": 1}, "version": "${String.repeat(
    "ab",
    32,
  )}", "state": {"name": "running", "address": "a", "runtime": "workerd", "isolation": ["isolate"]}}}`

test(
  "a control's target is its address, http or https with no query, and any other is ssh's",
  () => {
    deepEqual(Control.origin("control:http://localhost:8787/"), Some(Ok("http://localhost:8787")))
    deepEqual(Control.origin("control:https://c.example"), Some(Ok("https://c.example")))
    ok(Control.origin("control:localhost:8787")->Option.mapOr(false, Result.isError))
    deepEqual(
      Control.origin("control:https://c.example/v1/00000002/"),
      Some(Ok("https://c.example/v1/00000002")),
    )
    ok(Control.origin("control:https://c.example/v1?x=1")->Option.mapOr(false, Result.isError))
    deepEqual(Control.origin("root@machine.example"), None)
    deepEqual(Control.origin("local"), None)
  },
)

test("the gateway's address of an app is its scope under the control's origin, in hex", () => {
  deepEqual(
    Control.gateway(~origin="http://localhost:8787", ~app=3.),
    "http://localhost:8787/v1/00000003/",
  )
  deepEqual(
    Control.gateway(~origin="https://c.example", ~app=4275878552.),
    "https://c.example/v1/fedcba98/",
  )
})

testAsync(
  "a release is put, deployed and described as the operator, its secret the bearer",
  async () => {
    let (control, sent) = faked(
      dict{
        "/releases/put": (
          200,
          `{"status": "success", "data": {"hash": "${String.repeat("ab", 32)}", "size": 3}}`,
        ),
        "/releases/deploy": (200, described),
        "/releases/describe": (200, described),
      },
    )
    let held = await Control.put(control, Uint8Array.fromArray([1, 2, 3]))
    deepEqual(held->Result.map(h => Envelope.Hex.encode(h.hash)), Ok(String.repeat("ab", 32)))
    ok(
      (
        await Control.deploy(
          control,
          ~binding=2.,
          ~app=Some(1.),
          ~hash,
          ~secrets=dict{},
          ~network=[],
        )
      )->Result.isOk,
    )
    ok((await Control.describe(control, ~app=1.))->Result.isOk)
    deepEqual(
      sent->Array.map(s => (s.url, s.init.method, s.init.headers->Dict.get("authorization"))),
      [
        ("http://localhost:8787/releases/put", "POST", Some("Bearer the secret")),
        ("http://localhost:8787/releases/deploy", "POST", Some("Bearer the secret")),
        ("http://localhost:8787/releases/describe", "POST", Some("Bearer the secret")),
      ],
    )
    deepEqual(
      sent->Array.get(1)->Option.flatMap(s => s.init.body)->Option.map(b => JSON.parseOrThrow(b)),
      Some(
        JSON.parseOrThrow(
          `{"interface": "releases", "operation": "deploy", "input": {"binding": 2, "app": 1, "release": "${String.repeat(
              "ab",
              32,
            )}"}}`,
        ),
      ),
    )
  },
)

testAsync("a deploy hands the control the secrets and network it is given", async () => {
  let (control, sent) = faked(dict{"/releases/deploy": (200, described)})
  ignore(
    await Control.deploy(
      control,
      ~binding=1.,
      ~app=Some(2.),
      ~hash,
      ~secrets=dict{"OPERATOR": Bytes.utf8("kept")},
      ~network=[Http],
    ),
  )
  let input =
    sent
    ->Array.get(0)
    ->Option.flatMap(s => s.init.body)
    ->Option.map(b => JSON.parseOrThrow(b))
    ->Option.flatMap(JSON.Decode.object)
    ->Option.flatMap(o => o->Dict.get("input"))
    ->Option.flatMap(JSON.Decode.object)
  deepEqual(
    (
      input->Option.flatMap(i => i->Dict.get("secrets")),
      input->Option.flatMap(i => i->Dict.get("network")),
    ),
    (Some(JSON.parseOrThrow(`{"OPERATOR": "a2VwdA"}`)), Some(JSON.parseOrThrow(`["http"]`))),
  )
})

testAsync(
  "a refusal is its reason and message, and a control that does not answer unreached",
  async () => {
    let (control, _) = faked(
      dict{
        "/releases/deploy": (
          400,
          `{"status": "error", "failure": "rejected", "reason": "unbound", "message": "not bound"}`,
        ),
      },
    )
    deepEqual(
      await Control.deploy(
        control,
        ~binding=2.,
        ~app=Some(1.),
        ~hash,
        ~secrets=dict{},
        ~network=[],
      ),
      Error({reason: "unbound", message: "not bound"}),
    )
    deepEqual(
      (await Control.describe(control, ~app=1.))->Result.mapError(r => r.reason),
      Error("unreached"),
    )
  },
)

testAsync("the app is asked at the gateway, and only a gateway's 502 to 504 fails", async () => {
  let (control, sent) = faked(dict{"/v1/00000001/": (200, "hello from a machine\n")})
  deepEqual(await Control.asked(control, ~app=1.), Ok("200, hello from a machine"))
  deepEqual(
    sent->Array.map(s => (s.url, s.init.method)),
    [("http://localhost:8787/v1/00000001/", "GET")],
  )
  // The production control answers `/` with its own 400, which failed every deploy of it, rxmd9.
  let (refusing, _) = faked(
    dict{"/v1/00000002/": (400, "the path / is not /{interface}/{operation}")},
  )
  deepEqual(
    await Control.asked(refusing, ~app=2.),
    Ok("400, the path / is not /{interface}/{operation}"),
  )
  let (unbound, _) = faked(dict{"/v1/00000003/": (503, "the host of app 00000003 is not bound")})
  ok((await Control.asked(unbound, ~app=3.))->Result.isError)
})

testAsync(
  "a deploy with no app names none, and the control's answer gives the id it drew",
  async () => {
    let drawn = `{"status": "success", "data": {"runs": {"name": "app", "id": 2882400018}, "version": "${String.repeat(
        "ab",
        32,
      )}", "state": {"name": "making"}}}`
    let (control, sent) = faked(dict{"/releases/deploy": (200, drawn)})
    let answered = await Control.deploy(
      control,
      ~binding=2.,
      ~app=None,
      ~hash,
      ~secrets=dict{},
      ~network=[],
    )
    deepEqual(
      sent->Array.get(0)->Option.flatMap(s => s.init.body)->Option.map(b => JSON.parseOrThrow(b)),
      Some(
        JSON.parseOrThrow(
          `{"interface": "releases", "operation": "deploy", "input": {"binding": 2, "release": "${String.repeat(
              "ab",
              32,
            )}"}}`,
        ),
      ),
    )
    deepEqual(
      answered->Result.map(d =>
        switch d.runs {
        | App({id}) => Ids.text(id)
        | Component(_) => ""
        }
      ),
      Ok("abcdef12"),
    )
  },
)
