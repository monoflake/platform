/***
 * `Matching.matches` held to RFC p8e8k's rules: what the sample leaves out passed over, `$any`
 * present, `$absent` absent, `$capture` and `$use`, a list whole, and `$signed` read by the run's
 * trust before its claims are matched.
 */
open Node

let parse = JSON.parseOrThrow

let unsigned: Matching.signed = (_, _) => Error("nothing signed here")

let matches = (~signed=unsigned, ~captures=dict{}, expected, answered) =>
  Matching.matches(~expected=parse(expected), ~answered=parse(answered), ~signed, captures)

test("a field the sample leaves out is passed over", () => {
  deepEqual(matches(`{"size": 5}`, `{"size": 5, "content": "aGVsbG8", "later": true}`), Ok(dict{}))
  deepEqual(matches(`{}`, `{"size": 5}`), Ok(dict{}))
})

test("a field the sample writes is held, where it stands", () => {
  deepEqual(
    matches(`{"results": [{"changed": 1}]}`, `{"results": [{"changed": 2}]}`),
    Error({at: "results/0/changed", expected: "1", answered: "2"}),
  )
  deepEqual(matches(`{"size": 5}`, `{}`), Error({at: "size", expected: "5", answered: "absent"}))
  deepEqual(matches(`"a"`, `"b"`), Error({at: "", expected: `"a"`, answered: `"b"`}))
})

test("a list is held whole, its length as well", () => {
  deepEqual(matches(`[1, 2]`, `[1, 2]`), Ok(dict{}))
  deepEqual(matches(`[1, 2]`, `[1, 2, 3]`), Error({at: "", expected: "[1,2]", answered: "[1,2,3]"}))
})

test("$any is present with any value, and $absent absent", () => {
  deepEqual(matches(`{"at": {"$any": true}}`, `{"at": [1]}`), Ok(dict{}))
  deepEqual(
    matches(`{"at": {"$any": true}}`, `{}`),
    Error({at: "at", expected: `{"$any":true}`, answered: "absent"}),
  )
  deepEqual(matches(`{"size": {"$absent": true}}`, `{}`), Ok(dict{}))
  deepEqual(
    matches(`{"size": {"$absent": true}}`, `{"size": 0}`),
    Error({at: "size", expected: "absent", answered: "0"}),
  )
})

test("$capture records a value, and $use holds it the same as captured", () => {
  let captured = matches(`{"id": {"$capture": "id"}}`, `{"id": {"name": "a", "n": 3}}`)
  deepEqual(captured, Ok(dict{"id": parse(`{"name": "a", "n": 3}`)}))
  let captures = captured->Result.getOr(dict{})
  deepEqual(
    matches(~captures, `{"id": {"$use": "id"}}`, `{"id": {"n": 3, "name": "a"}}`),
    Ok(captures),
  )
  deepEqual(
    matches(~captures, `{"id": {"$use": "id"}}`, `{"id": {"name": "a"}}`),
    Error({at: "id", expected: `{"name":"a","n":3}`, answered: `{"name":"a"}`}),
  )
  ok(matches(`{"id": {"$use": "none"}}`, `{"id": 1}`)->Result.isError)
})

test("$signed is verified by the run's trust, then its claims matched as any value is", () => {
  let signed: Matching.signed = (bytes, record) =>
    record == "capability" && bytes == Uint8Array.fromArray([1, 2, 3])
      ? Ok(parse(`{"sub": "00000007", "scope": 1, "rights": ["read"]}`))
      : Error("a signature its signer's key does not verify")
  let expected = `{"capability": {"$signed": {"record": "capability", "claims": {"sub": "00000007", "rights": {"$capture": "rights"}}}}}`
  deepEqual(
    matches(~signed, expected, `{"capability": "AQID"}`),
    Ok(dict{"rights": parse(`["read"]`)}),
  )
  deepEqual(
    matches(~signed, expected, `{"capability": "AQIE"}`),
    Error({
      at: "capability",
      expected: "a capability verified",
      answered: "a signature its signer's key does not verify",
    }),
  )
  deepEqual(
    matches(
      ~signed,
      `{"capability": {"$signed": {"record": "capability", "claims": {"sub": "00000008"}}}}`,
      `{"capability": "AQID"}`,
    ),
    Error({at: "capability/sub", expected: `"00000008"`, answered: `"00000007"`}),
  )
})
