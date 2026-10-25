/***
 * `Bearer` held to running each case in each form on a binding of its own, against a server that
 * keeps each token's objects apart and denies a call with none.
 */
open Node

let address = server => `http://localhost:${Int.toString((server->address).port)}`

/** A case writing `a` and one finding it absent, which only a binding of its own lets hold. */
let file = switch Sample.read(`{
  "interface": "object",
  "cases": [
    {
      "description": "an object written is read",
      "steps": [
        {"call": "write", "input": {"name": "a", "content": "aGk"}, "expect": {"output": {}}},
        {"call": "read", "input": {"name": "a"}, "expect": {"output": {"content": "aGk", "size": 2}}}
      ]
    },
    {
      "description": "a binding new holds no object",
      "steps": [
        {"call": "read", "input": {"name": "a"}, "expect": {"failure": "rejected", "reason": "not_found"}}
      ]
    }
  ]
}`) {
| Ok(file) => file
| Error(why) => JsError.throwWithMessage(why)
}

let tokens = ["1.a", "2.b", "3.c", "4.d"]

/** Each token taken in turn, or the first alone where `shared`. */
let taking = (~shared) => {
  let taken = ref(-1)
  () => {
    taken := (shared ? 0 : taken.contents + 1)
    tokens->Array.get(taken.contents)->Option.getOr("")
  }
}

let outcomes = results =>
  results->Array.map(((case: Sample.case, result: Run.result_)) => (
    case.description,
    result.outcomes->Array.map(((_, outcome)) =>
      switch outcome {
      | Run.Passed => "passed"
      | Failed(_) => "failed"
      | Skipped(_) => "skipped"
      }
    ),
  ))

test("tokens are a file's lines, its blank ones passed over", () =>
  deepEqual(Bearer.tokens("1.a\n\n  2.b  \n"), ["1.a", "2.b"])
)

testAsync(
  "each case in each form runs on a binding of its own, its token taken in turn",
  async () => {
    let server = await Server.start(~tokens)
    let at = (~token) => Http.target(~base=address(server), ~chain=None, ~bounds=dict{}, ~token)
    let own = await Bearer.file(file, ~at, ~next=taking(~shared=false))
    let shared = await Bearer.file(file, ~at, ~next=taking(~shared=true))
    let unbound = await Http.target(~base=address(server), ~chain=None, ~bounds=dict{}).call(
      ~interface="object",
      ~operation="read",
      ~input=JSON.parseOrThrow(`{"name": "a"}`),
      ~form=Json,
      ~as_=None,
      ~bearer=None,
    )
    await stop(server)
    deepEqual(
      outcomes(own),
      [
        ("an object written is read", ["passed", "passed"]),
        ("a binding new holds no object", ["passed", "passed"]),
      ],
    )
    // On one binding the second case finds what the first wrote.
    deepEqual(
      outcomes(shared),
      [
        ("an object written is read", ["passed", "passed"]),
        ("a binding new holds no object", ["failed", "failed"]),
      ],
    )
    switch unbound {
    | Ok(Failed({reason})) => deepEqual(reason, "denied")
    | Ok(Answered(_)) | Error(_) => ok(false, ~message="a call with no token is not denied")
    }
  },
)

test(
  "split calls, holds and sends in CBOR through one target and in JSON through the other",
  () => {
    let called = []
    let target = (name): Run.target => {
      call: async (
        ~interface as _,
        ~operation as _,
        ~input as _,
        ~form as _,
        ~as_ as _,
        ~bearer as _,
      ) => {
        called->Array.push(name)
        Ok(Answered(JSON.Null))
      },
      send: async (~to as _, ~export as _, ~key as _, ~body as _, ~form as _) => {
        called->Array.push(`${name} send`)
        Error("none")
      },
      given: async (~interface as _, ~form as _, _) => {
        called->Array.push(`${name} given`)
        Ok()
      },
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
    let split = Bearer.split(~cbor=target("cbor"), ~json=target("json"))
    let call = form =>
      split.call(
        ~interface="object",
        ~operation="read",
        ~input=JSON.Null,
        ~form,
        ~as_=None,
        ~bearer=None,
      )->ignore
    call(Json)
    call(Cbor)
    split.given(~interface="object", ~form=Json, None)->ignore
    split.given(~interface="object", ~form=Cbor, None)->ignore
    split.send(~to="a", ~export="echo", ~key=None, ~body=None, ~form=Json)->ignore
    deepEqual(called, ["json", "cbor", "json given", "cbor given", "json send"])
  },
)
