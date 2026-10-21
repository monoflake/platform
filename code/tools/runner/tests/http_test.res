/***
 * `Http.target` end to end: the block's own `tests/objects.json` run against a server answering
 * `object` by the `answer` envelope, in CBOR and in JSON; a call made `as` a component signed by
 * the chain the run made, its certificate verified to that root; a body that is no answer read as
 * `unknown`; and a record no chain of the run signed refused.
 */
open Node

let address = server => `http://localhost:${Int.toString((server->address).port)}`

testAsync("a behavior file runs through HTTP, every case in both forms", async () => {
  let server = await Server.start()
  let chain = Http.chain(~components=["compute"], ~now=Date.now())
  let target = Http.target(~base=address(server), ~chain=Some(chain), ~bounds=dict{"content": 16.})
  let file = switch Sample.read(readFileSync(fromBlock("tests/objects.json"))) {
  | Ok(file) => file
  | Error(why) => JsError.throwWithMessage(why)
  }
  let results = await Run.file(file, target)
  await stop(server)
  let both = (outcome: Run.outcome) => [(Run.Cbor, outcome), (Json, outcome)]
  deepEqual(
    results,
    [
      {description: "an object written is read whole, and described", outcomes: both(Passed)},
      {description: "an object absent is not found", outcomes: both(Passed)},
      {description: "bytes made to a bound are written as made", outcomes: both(Passed)},
      {
        description: "a call made as a component carries its certificate, which verifies to the run's root",
        outcomes: both(Passed),
      },
      {
        description: "a body that is no answer is unknown, whatever its HTTP status",
        outcomes: both(Passed),
      },
      {
        description: "a case given what the target cannot set up is skipped",
        outcomes: both(
          Skipped(
            "a case's given, set up through the contracts above the implementation: not offered by this target, left for later by RFC p8e8k",
          ),
        ),
      },
    ],
  )
})

testAsync("an answer is read by its status, in the form asked", async () => {
  let server = await Server.start()
  let target = Http.target(~base=address(server), ~chain=None, ~bounds=dict{})
  let call = (operation, input, form) =>
    target.call(~interface="object", ~operation, ~input=JSON.parseOrThrow(input), ~form, ~as_=None)
  let forms = [Run.Cbor, Json]
  for i in 0 to 1 {
    let form = forms->Array.get(i)->Option.getOr(Cbor)
    deepEqual(
      await call("write", `{"name": "a", "content": "aGk"}`, form),
      Ok(Answered(JSON.parseOrThrow("{}"))),
    )
    deepEqual(
      await call("read", `{"name": "a"}`, form),
      Ok(Answered(JSON.parseOrThrow(`{"content": "aGk", "size": 2}`))),
    )
    deepEqual(
      await call("read", `{"name": "b"}`, form),
      Ok(Failed({failure: "rejected", reason: "not_found", message: "no such object"})),
    )
    // A proxy's 502, its body no answer, is unknown whatever was asked.
    ok(
      switch await call("list", `{"prefix": ""}`, form) {
      | Ok(Failed({failure: "unknown", reason: "malformed", message})) =>
        message->String.startsWith("HTTP 502, its body no answer")
      | Ok(Answered(_) | Failed(_)) | Error(_) => false
      },
    )
  }
  // A call made as a component without a chain is no call the target can make.
  deepEqual(
    await target.call(
      ~interface="object",
      ~operation="read",
      ~input=JSON.parseOrThrow(`{"name": "a"}`),
      ~form=Cbor,
      ~as_=Some("compute"),
    ),
    Error("no chain the run made to sign as compute"),
  )
  await stop(server)
})

testAsync(
  "a record is verified to the run's root, and one another chain signed is refused",
  async () => {
    let server = await Server.start()
    let chain = Http.chain(~components=["compute"], ~now=Date.now())
    let other = Http.chain(~components=["compute"], ~now=Date.now())
    ok(Http.root(chain) != Http.root(other))
    deepEqual(TypedArray.length(Http.root(chain)), 32)
    let ours = Http.target(~base=address(server), ~chain=Some(chain), ~bounds=dict{})
    let theirs = Http.target(~base=address(server), ~chain=Some(other), ~bounds=dict{})
    // The server keeps the certificate a signed call carried as what it wrote.
    let written = await theirs.call(
      ~interface="object",
      ~operation="write",
      ~input=JSON.parseOrThrow(`{"name": "who", "content": "AA"}`),
      ~form=Cbor,
      ~as_=Some("compute"),
    )
    deepEqual(written, Ok(Answered(JSON.parseOrThrow("{}"))))
    let read = await ours.call(
      ~interface="object",
      ~operation="read",
      ~input=JSON.parseOrThrow(`{"name": "who"}`),
      ~form=Json,
      ~as_=None,
    )
    await stop(server)
    let certificate = switch read {
    | Ok(Answered(json)) =>
      json
      ->JSON.Decode.object
      ->Option.flatMap(o => o->Dict.get("content"))
      ->Option.flatMap(JSON.Decode.string)
      ->Option.flatMap(Envelope.Base64url.decode)
      ->Option.getOr(Uint8Array.fromLength(0))
    | Ok(Failed(_)) | Error(_) => Uint8Array.fromLength(0)
    }
    deepEqual(
      ours.signed(certificate, "certificate"),
      Error("a kid of no certificate the run made, nor its root's"),
    )
    ok(
      switch theirs.signed(certificate, "certificate") {
      | Ok(claims) =>
        claims->JSON.Decode.object->Option.flatMap(o => o->Dict.get("sub")) ==
          Some(JSON.String("compute"))
      | Error(_) => false
      },
    )
    deepEqual(
      ours.signed(Uint8Array.fromArray([1, 2]), "capability"),
      Error("malformed: no deterministic CBOR"),
    )
    deepEqual(ours.signed(certificate, "nothing"), Error("no signed record nothing"))
    let unchained = Http.target(~base="http://localhost:1", ~chain=None, ~bounds=dict{})
    deepEqual(
      unchained.signed(certificate, "certificate"),
      Error("no chain the run made to verify by"),
    )
  },
)
