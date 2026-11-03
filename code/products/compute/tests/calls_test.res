open Node

let json = JSON.parseOrThrow
let empty = json(`{"Ok":{"results":[{"columns":[],"rows":[],"changed":0}]}}`)
let fake = answer => {
  let statements = []
  let execute = async input => {
    statements->Array.push(input)
    answer
  }
  (execute, statements)
}

testAsync("issued ids rise within a millisecond and across a clock rollback", async () => {
  let issuer = Calls.issuer()
  deepEqual(Calls.issued(issuer, ~now=42.), Some("00000000002a0000"))
  deepEqual(Calls.issued(issuer, ~now=42.), Some("00000000002a0001"))
  deepEqual(Calls.issued(issuer, ~now=1.), Some("00000000002a0002"))
  deepEqual(Calls.issued(issuer, ~now=43.), Some("00000000002b0000"))
})

testAsync("issued refuses sequence 65536 and resumes at the next millisecond", async () => {
  let issuer = Calls.issuer()
  for sequence in 0 to 65535 {
    let id = Calls.issued(issuer, ~now=100.)
    deepEqual(id->Option.isSome, true)
    if sequence == 65535 {
      deepEqual(id, Some("000000000064ffff"))
    }
  }
  deepEqual(Calls.issued(issuer, ~now=100.), None)
  deepEqual(Calls.issued(issuer, ~now=99.), None)
  deepEqual(Calls.issued(issuer, ~now=101.), Some("0000000000650000"))
})

testAsync("issuedAt round trips the full 48 bit timestamp and rejects malformed ids", async () => {
  [0., 1., 1793700000123., 281474976710655.]->Array.forEach(now => {
    let issuer = Calls.issuer()
    deepEqual(Calls.issued(issuer, ~now)->Option.flatMap(Calls.issuedAt), Some(now))
  })
  deepEqual(Calls.issued(Calls.issuer(), ~now=281474976710655.), Some("ffffffffffff0000"))
  [
    "",
    "000000000000000",
    "00000000000000000",
    "FFFFFFFFFFFFFFFF",
    "000000000000000g",
    "0000000000000000\n",
  ]->Array.forEach(id => deepEqual(Calls.issuedAt(id), None))
  [-1., 0.5, 281474976710656.]->Array.forEach(now =>
    deepEqual(Calls.issued(Calls.issuer(), ~now), None)
  )
})

testAsync("made creates the calls table if absent", async () => {
  let (execute, statements) = fake(empty)
  deepEqual(await Calls.made(~execute), Ok())
  deepEqual(
    statements,
    [
      json(`{"statements":[{"sql":"CREATE TABLE IF NOT EXISTS calls(id TEXT PRIMARY KEY, app INTEGER, function TEXT, expires INTEGER, outcome TEXT)","parameters":[]}]}`),
    ],
  )
})

let record: Calls.record = {
  id: "00000000002a0001",
  app: 4294967295.,
  function: "send'payment",
  expires: 60123.,
  outcome: Some("success"),
}

testAsync("recorded inserts typed parameters with no outcome yet", async () => {
  let (execute, statements) = fake(empty)
  deepEqual(await Calls.recorded(~execute, record), Ok())
  deepEqual(
    statements,
    [
      json(`{"statements":[{"sql":"INSERT INTO calls(id, app, function, expires, outcome) VALUES (?, ?, ?, ?, ?)","parameters":[{"name":"text","value":"00000000002a0001"},{"name":"integer","value":4294967295},{"name":"text","value":"send'payment"},{"name":"integer","value":60123},{"name":"null"}]}]}`),
    ],
  )
})

testAsync("told updates only the named call using typed parameters", async () => {
  let (execute, statements) = fake(empty)
  deepEqual(await Calls.told(~execute, ~id=record.id, ~outcome="success"), Ok())
  deepEqual(
    statements,
    [
      json(`{"statements":[{"sql":"UPDATE calls SET outcome = ? WHERE id = ?","parameters":[{"name":"text","value":"success"},{"name":"text","value":"00000000002a0001"}]}]}`),
    ],
  )
})

testAsync("found reads a record and its nullable outcome with a parameterized id", async () => {
  let answer = json(`{"Ok":{"results":[{"columns":["id","app","function","expires","outcome"],"rows":[[{"name":"text","value":"00000000002a0001"},{"name":"integer","value":4294967295},{"name":"text","value":"send'payment"},{"name":"integer","value":60123},{"name":"text","value":"success"}]],"changed":0}]}}`)
  let (execute, statements) = fake(answer)
  deepEqual(await Calls.found(~execute, ~id=record.id), Ok(Some(record)))
  deepEqual(
    statements,
    [
      json(`{"statements":[{"sql":"SELECT id, app, function, expires, outcome FROM calls WHERE id = ?","parameters":[{"name":"text","value":"00000000002a0001"}]}]}`),
    ],
  )
  let (execute, _) = fake(
    json(`{"Ok":{"results":[{"columns":["id","app","function","expires","outcome"],"rows":[[{"name":"text","value":"00000000002a0001"},{"name":"integer","value":4294967295},{"name":"text","value":"send'payment"},{"name":"integer","value":60123},{"name":"null"}]],"changed":0}]}}`),
  )
  deepEqual(await Calls.found(~execute, ~id=record.id), Ok(Some({...record, outcome: None})))
})

testAsync("found returns none for an absent call", async () => {
  let (execute, _) = fake(empty)
  deepEqual(await Calls.found(~execute, ~id=record.id), Ok(None))
})

testAsync("database errors preserve their reason in every operation", async () => {
  let (execute, _) = fake(json(`{"Error":{"reason":"storage_full","kind":"unavailable"}}`))
  deepEqual(await Calls.made(~execute), Error("storage_full"))
  deepEqual(await Calls.recorded(~execute, record), Error("storage_full"))
  deepEqual(await Calls.told(~execute, ~id=record.id, ~outcome="unknown"), Error("storage_full"))
  deepEqual(await Calls.found(~execute, ~id=record.id), Error("storage_full"))
})

testAsync("found refuses malformed results and rows", async () => {
  let answers = [
    `{}`,
    `{"Ok":{"results":[]}}`,
    `{"Ok":{"results":[{"rows":[[]]}]}}`,
    `{"Ok":{"results":[{"rows":[[{"name":"text","value":"id"},{"name":"text","value":"bad"},{"name":"text","value":"function"},{"name":"integer","value":123},{"name":"null"}]]}]}}`,
  ]
  for index in 0 to answers->Array.length - 1 {
    let answer = answers->Array.getUnsafe(index)
    let (execute, _) = fake(json(answer))
    deepEqual(
      await Calls.found(~execute, ~id=record.id),
      Error("the records database answered an invalid result"),
    )
  }
})
