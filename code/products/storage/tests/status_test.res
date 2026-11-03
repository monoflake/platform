open Node
module Contracts = Envelope.Contracts

let field = (json, name) =>
  json->JSON.Decode.object->Option.getOrThrow->Dict.get(name)->Option.getOrThrow

let items = json => json->JSON.Decode.array->Option.getOrThrow

let env = (kind: Kind.t): Worker.env => {
  socket: "data",
  salt: String.repeat("ab", 32),
  objects: kind.fetcher,
}

let request = (~headers=dict{"Caller": "0000002a"}, ~method="POST", input) =>
  Kind.asRequest(
    Web.request(
      "http://storage/storage/status",
      {
        method,
        headers,
        body: ?(method == "GET" ? None : Some(JSON.stringify(input))),
      },
    ),
  )

let fetched = async (request, env) => {
  let response = Kind.ofResponse(await Worker.fetch(request, env))
  (response->Web.status, JSON.parseOrThrow(await response->Web.text))
}

let errorOf = json =>
  switch Contracts.Answer.fromJson(json, Contracts.CallSteps.fromJson) {
  | Ok(Error({failure, reason})) => Some((failure, reason))
  | Ok(Success(_)) | Error(_) => None
  }

testAsync(
  "storage status samples pass the kind's call steps and reasons through OBJECT",
  async () => {
    let samples =
      Runs.readText(Runs.url("../../../../tests/products/storage/status.json", Runs.moduleUrl))
      ->JSON.parseOrThrow
      ->field("cases")
      ->items
    deepEqual(samples->Array.length, 3)
    for index in 0 to samples->Array.length - 1 {
      let sample = samples->Array.getUnsafe(index)
      let step = sample->field("steps")->items->Array.getUnsafe(0)
      let input = step->field("input")
      let expected = step->field("expect")
      let fields = expected->JSON.Decode.object->Option.getOrThrow
      let answer = switch fields->Dict.get("output") {
      | Some(output) => JSON.Object(dict{"status": String("success"), "data": output})
      | None =>
        JSON.Object(
          dict{
            "status": String("error"),
            "failure": expected->field("failure"),
            "reason": expected->field("reason"),
            "message": String("The kind's status message"),
          },
        )
      }
      let kind = Kind.make()
      kind.replaced := Some((200, JSON.stringify(answer)))
      deepEqual(await fetched(request(input), env(kind)), (200, answer))
      deepEqual(
        kind.sent,
        [
          {
            url: "http://object/object/status",
            method: "POST",
            contentType: Some("application/json"),
            body: JSON.Object(
              dict{
                "interface": String("object"),
                "operation": step->field("call"),
                "input": input,
              },
            ),
          },
        ],
      )
    }
  },
)

testAsync("status refuses a bucket key and malformed ids before reaching OBJECT", async () => {
  let kind = Kind.make()
  let invalid = [JSON.Null, JSON.Object(dict{}), JSON.Object(dict{"id": Number(1.)})]
  let buckets = [JSON.Null, JSON.Number(1.), JSON.String("objects")]
  buckets->Array.forEach(bucket => {
    invalid->Array.push(JSON.Object(dict{"id": String("call"), "bucket": bucket}))
  })
  for index in 0 to invalid->Array.length - 1 {
    let input = invalid->Array.getUnsafe(index)
    let (status, answer) = await fetched(request(input), env(kind))
    deepEqual((status, errorOf(answer)), (200, Some((Contracts.Failure.Rejected, "malformed"))))
  }
  deepEqual(kind.sent, [])
})

testAsync("status requires Caller and POST on data and is refused on public", async () => {
  let kind = Kind.make()
  let input = Contracts.ObjectStatus.toJson({id: "call"})
  let refused = [
    (request(~headers=dict{}, input), env(kind)),
    (request(~headers=dict{"Caller": "bad"}, input), env(kind)),
    (request(~method="GET", input), env(kind)),
    (request(input), {...env(kind), socket: "public"}),
  ]
  for index in 0 to refused->Array.length - 1 {
    let (request, env) = refused->Array.getUnsafe(index)
    let (status, answer) = await fetched(request, env)
    deepEqual((status, errorOf(answer)), (403, Some((Contracts.Failure.Rejected, "forbidden"))))
  }
  deepEqual(kind.sent, [])
})

testAsync(
  "status preserves finished steps and turns a malformed kind answer into fault",
  async () => {
    let kind = Kind.make()
    let input = Contracts.ObjectStatus.toJson({id: "call"})
    let steps: Contracts.CallSteps.t = {committed: [1., 3.], expires: 1234., finished: true}
    let answer = Contracts.Answer.toJson(Success(steps), Contracts.CallSteps.toJson)
    kind.replaced := Some((200, JSON.stringify(answer)))
    deepEqual(await fetched(request(input), env(kind)), (200, answer))
    kind.replaced := Some((200, `{"status":"success","data":{}}`))
    let (status, answer) = await fetched(request(input), env(kind))
    deepEqual((status, errorOf(answer)), (200, Some((Contracts.Failure.Unknown, "fault"))))
  },
)
