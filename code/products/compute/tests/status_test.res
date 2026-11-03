open Node

let issued = 1000.
let retention = 86400000.
let expires = 61000.
let id = "0000000003e80000"

let answered = (~recorded, ~steps, ~now=issued, ()) =>
  Status.answered(~recorded, ~steps, ~issued, ~now, ~retention)

let errorJson = reason => JSON.Object(
  dict{
    "Error": JSON.Object(
      dict{
        "failure": JSON.String("rejected"),
        "reason": JSON.String(reason),
        "message": JSON.String(Envelope.Contracts.messages->Dict.get(reason)->Option.getOrThrow),
      },
    ),
  },
)

testAsync("status forgets past retention with and without a surviving record", async () => {
  [None, Some((expires, Some("success")))]->Array.forEach(recorded => {
    let answer = answered(
      ~recorded,
      ~steps=Some(([1, 2], true)),
      ~now=issued +. retention +. 1.,
      (),
    )
    deepEqual(answer, Status.Forgotten)
    deepEqual(Status.json(~id, answer), errorJson("forgotten"))
  })
})

testAsync("status reports not found without a record even when steps answered", async () => {
  [None, Some(([1], true))]->Array.forEach(steps => {
    let answer = answered(~recorded=None, ~steps, ())
    deepEqual(answer, Status.NotFound)
    deepEqual(Status.json(~id, answer), errorJson("not_found"))
  })
})

testAsync("status retains known and absent calls at the retention boundary", async () => {
  let now = issued +. retention
  deepEqual(answered(~recorded=None, ~steps=None, ~now, ()), Status.NotFound)
  deepEqual(
    answered(~recorded=Some((expires, None)), ~steps=None, ~now, ()),
    Status.Known({outcome: None, committed: [], expires, finished: false}),
  )
})

testAsync("status preserves the recorded outcome and every step that answered", async () => {
  let answer = answered(
    ~recorded=Some((expires, Some("unknown"))),
    ~steps=Some(([1, 3, 7], true)),
    (),
  )
  deepEqual(
    answer,
    Status.Known({outcome: Some("unknown"), committed: [1, 3, 7], expires, finished: true}),
  )
  deepEqual(
    Status.json(~id, answer),
    JSON.parseOrThrow(
      `{"Ok":{"id":"${id}","outcome":"unknown","committed":[1,3,7],"expires":61000,"finished":true}}`,
    ),
  )
})

testAsync("status defaults unanswered steps without changing a recorded outcome", async () => {
  let answer = answered(~recorded=Some((expires, Some("rejected"))), ~steps=None, ())
  deepEqual(
    answer,
    Status.Known({outcome: Some("rejected"), committed: [], expires, finished: false}),
  )
  deepEqual(
    Status.json(~id, answer),
    JSON.parseOrThrow(
      `{"Ok":{"id":"${id}","outcome":"rejected","committed":[],"expires":61000,"finished":false}}`,
    ),
  )
})

testAsync("status omits an untold outcome with and without steps", async () => {
  [None, Some(([2], false))]->Array.forEach(steps => {
    let answer = answered(~recorded=Some((expires, None)), ~steps, ())
    let committed = steps->Option.mapOr([], ((committed, _)) => committed)
    deepEqual(answer, Status.Known({outcome: None, committed, expires, finished: false}))
    deepEqual(
      Status.json(~id, answer),
      JSON.Object(
        dict{
          "Ok": JSON.Object(
            dict{
              "id": JSON.String(id),
              "committed": JSON.Array(committed->Array.map(step => JSON.Number(step->Int.toFloat))),
              "expires": JSON.Number(expires),
              "finished": JSON.Boolean(false),
            },
          ),
        },
      ),
    )
  })
})
