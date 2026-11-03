open Node

testAsync("classified tells success for 2xx answers without failure", async () => {
  deepEqual(Outcome.classified(Answered({status: 200, failure: None})), Told(Success))
  deepEqual(Outcome.classified(Answered({status: 204, failure: None})), Told(Success))
})

testAsync("classified tells success for 4xx answers without failure", async () => {
  deepEqual(Outcome.classified(Answered({status: 400, failure: None})), Told(Success))
  deepEqual(Outcome.classified(Answered({status: 499, failure: None})), Told(Success))
})

testAsync("classified looks up 500 and 503 answers without failure", async () => {
  deepEqual(Outcome.classified(Answered({status: 500, failure: None})), Look)
  deepEqual(Outcome.classified(Answered({status: 503, failure: None})), Look)
})

testAsync("classified tells rejected from the failure regardless of status", async () => {
  deepEqual(Outcome.classified(Answered({status: 400, failure: Some("rejected")})), Told(Rejected))
  deepEqual(Outcome.classified(Answered({status: 500, failure: Some("rejected")})), Told(Rejected))
})

testAsync("classified tells unavailable from the failure regardless of status", async () => {
  deepEqual(
    Outcome.classified(Answered({status: 503, failure: Some("unavailable")})),
    Told(Unavailable),
  )
  deepEqual(
    Outcome.classified(Answered({status: 200, failure: Some("unavailable")})),
    Told(Unavailable),
  )
})

testAsync("classified looks up unknown failure", async () => {
  deepEqual(Outcome.classified(Answered({status: 200, failure: Some("unknown")})), Look)
})

testAsync("classified looks up an unrecognized failure name", async () => {
  deepEqual(Outcome.classified(Answered({status: 400, failure: Some("unexpected")})), Look)
})

testAsync("classified tells unavailable for Unsent and looks up Lost", async () => {
  deepEqual(Outcome.classified(Unsent), Told(Unavailable))
  deepEqual(Outcome.classified(Lost), Look)
})

testAsync("name spells every call outcome", async () => {
  deepEqual(Outcome.name(Success), "success")
  deepEqual(Outcome.name(Rejected), "rejected")
  deepEqual(Outcome.name(Unavailable), "unavailable")
  deepEqual(Outcome.name(Unknown), "unknown")
})

testAsync("failureOf reads the failure of an Error answer", async () => {
  deepEqual(
    Outcome.failureOf(JSON.parseOrThrow(`{"Error":{"failure":"rejected"}}`)),
    Some("rejected"),
  )
  deepEqual(
    Outcome.failureOf(JSON.parseOrThrow(`{"Error":{"failure":"unexpected"}}`)),
    Some("unexpected"),
  )
})

testAsync("failureOf finds no failure in an Ok answer", async () => {
  deepEqual(Outcome.failureOf(JSON.parseOrThrow(`{"Ok":{"failure":"rejected"}}`)), None)
})

testAsync("failureOf finds no failure in other JSON or malformed Error answers", async () => {
  let bodies = [
    `null`,
    `false`,
    `42`,
    `"rejected"`,
    `[]`,
    `{}`,
    `{"failure":"rejected"}`,
    `{"Error":null}`,
    `{"Error":"rejected"}`,
    `{"Error":[]}`,
    `{"Error":{}}`,
    `{"Error":{"failure":null}}`,
    `{"Error":{"failure":42}}`,
    `{"Error":{"failure":{}}}`,
  ]
  bodies->Array.forEach(body => deepEqual(Outcome.failureOf(JSON.parseOrThrow(body)), None))
})
