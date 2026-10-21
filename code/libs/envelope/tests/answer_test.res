/***
 * `Contracts.Answer` held to `model/contracts.json`'s `answer`, RFC ge55b, as `answer.rs` is in
 * Rust.
 */
open Node
open Sample

module Answer = Contracts.Answer
module Named = Contracts.ObjectName

let toJson = answer => Answer.toJson(answer, Named.toJson)
let fromJson = json => Answer.fromJson(json, Named.fromJson)
let toCbor = answer => Answer.toCbor(answer, Named.toCbor)
let fromCbor = bytes => Answer.fromCbor(decoded(bytes), Named.fromCbor)

let gone: Answer.t<Named.t> = Error({failure: Rejected, reason: "not_found", message: "gone"})

let malformed = (at, expected): result<Answer.t<Named.t>, Malformed.t> => Error({at, expected})

test("a success holds the output as data", () => {
  let answer: Answer.t<Named.t> = Success({name: "a"})
  let json = parse(`{"status": "success", "data": {"name": "a"}}`)
  deepEqual(toJson(answer), json)
  deepEqual(fromJson(json), Ok(answer))
  // `{0: 1, 1: {1: "a"}}`
  deepEqual(encoded(toCbor(answer)), hex("a2000101a1016161"))
  deepEqual(fromCbor(hex("a2000101a1016161")), Ok(answer))
})

test("an error holds its fields beside the status", () => {
  let json = parse(`{"status": "error", "failure": "rejected", "reason": "not_found", "message": "gone"}`)
  deepEqual(toJson(gone), json)
  deepEqual(fromJson(json), Ok(gone))
  // `{0: 2, 1: 1, 2: "not_found", 3: "gone"}`
  let cbor = hex("a40002010102696e6f745f666f756e640364676f6e65")
  deepEqual(encoded(toCbor(gone)), cbor)
  deepEqual(fromCbor(cbor), Ok(gone))
})

test("a field no reader knows is passed over", () => {
  deepEqual(
    fromJson(parse(`{"status": "success", "data": {"name": "a"}, "message": 1}`)),
    Ok(Success({name: "a"})),
  )
  deepEqual(
    fromJson(
      parse(`{"status": "error", "failure": "rejected", "reason": "not_found", "message": "gone", "data": {}}`),
    ),
    Ok(gone),
  )
  // `{0: 2, 1: 1, 2: "not_found", 3: "gone", 9: true}`
  deepEqual(fromCbor(hex("a50002010102696e6f745f666f756e640364676f6e6509f5")), Ok(gone))
})

test("a status neither case names is refused at status", () => {
  deepEqual(
    fromJson(parse(`{"status": "done", "data": {}}`)),
    malformed([Field("status")], "one of success, error"),
  )
  deepEqual(fromJson(parse(`{"data": {"name": "a"}}`)), malformed([Field("status")], "present"))
  deepEqual(fromJson(parse(`{"status": 1}`)), malformed([Field("status")], "a string"))
  // `{0: 3}`
  deepEqual(fromCbor(hex("a10003")), malformed([Field("status")], "one of 1, 2"))
  deepEqual(fromCbor(hex("a0")), malformed([Field("status")], "present"))
  deepEqual(fromJson(parse(`[]`)), malformed([], "an object"))
})

test("what a case holds is read as its type", () => {
  deepEqual(
    fromJson(parse(`{"status": "success", "data": {"name": 1}}`)),
    malformed([Field("data"), Field("name")], "a string"),
  )
  deepEqual(fromJson(parse(`{"status": "success"}`)), malformed([Field("data")], "present"))
  deepEqual(
    fromJson(parse(`{"status": "error", "failure": "lost", "reason": "x", "message": "y"}`)),
    malformed([Field("failure")], "one of rejected, unavailable, unknown"),
  )
})

test("an error without its message is refused", () => {
  deepEqual(
    fromJson(parse(`{"status": "error", "failure": "rejected", "reason": "not_found"}`)),
    malformed([Field("message")], "present"),
  )
  // `{0: 2, 1: 1, 2: "not_found"}`
  deepEqual(
    fromCbor(hex("a30002010102696e6f745f666f756e64")),
    malformed([Field("message")], "present"),
  )
  deepEqual(
    Contracts.jsonToCbor("error", parse(`{"failure": "rejected", "reason": "not_found"}`)),
    Some(Error({at: [Field("message")], expected: "present"})),
  )
})

/** `model/contracts.json`'s `messages`, as it stands. */
let messages = () =>
  switch readFileSync(fromRoot("model/contracts.json"))
  ->parse
  ->member("messages")
  ->JSON.Decode.object {
  | Some(messages) => messages
  | None => fail("model/contracts.json: no messages")
  }

let carried = (reasons: array<Contracts.reason>) => {
  ok(reasons->Array.length > 0)
  let messages = messages()
  reasons->Array.forEach(reason => {
    deepEqual(
      messages->Dict.get(reason.name)->Option.flatMap(JSON.Decode.string),
      Some(reason.message),
      ~message=reason.name,
    )
    deepEqual(Contracts.messages->Dict.get(reason.name), Some(reason.message), ~message=reason.name)
  })
}

test("every reason carries the message messages gives it", () => {
  carried(Contracts.reasons)
  carried(Contracts.calling)
  carried(Contracts.Interface.Object.write.reasons)
  carried(Contracts.Interface.Object.read.reasons)
  carried(Contracts.Interface.Database.execute.reasons)
  messages()
  ->Dict.toArray
  ->Array.forEach(((name, message)) =>
    deepEqual(Contracts.messages->Dict.get(name), message->JSON.Decode.string, ~message=name)
  )
  deepEqual(Contracts.messages->Dict.get("not_found"), Some("Nothing of that name or id exists"))
  deepEqual(Contracts.messages->Dict.get("no_such_reason"), None)
})
