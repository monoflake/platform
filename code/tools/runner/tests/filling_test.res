/***
 * `Filling.fill` and `Filling.bytes` held to RFC p8e8k: the same bytes every run, of the case's
 * description, the step's index and the value's path; every placeholder an input takes made, and
 * what the run offers not refused as not offered.
 */
open Node

let parse = JSON.parseOrThrow

let context: Filling.context = {
  description: "an object written is read whole",
  step: 2,
  captures: dict{"address": JSON.String("http://localhost:8787")},
  now: 1_800_000_000_000.,
  bound: name => name == "content" ? Some(8.) : None,
  fixture: name => name == "echo-modules" ? Some(String.repeat("ab", 32)) : None,
}

let hex = Envelope.Hex.encode

test("$bytes are the BLAKE3 output of description, step and path, the same every time", () => {
  let made = Filling.bytes(~description="d", ~step=0, ~path="content", 8)
  deepEqual(TypedArray.length(made), 8)
  deepEqual(made, Filling.bytes(~description="d", ~step=0, ~path="content", 8))
  // BLAKE3 of "d/0/content", its first 8 bytes.
  deepEqual(hex(made), "a61de286dc0fe80e")
  // The output is extendable: a longer read begins with the shorter.
  deepEqual(
    Filling.bytes(~description="d", ~step=0, ~path="content", 16)->TypedArray.slice(
      ~start=0,
      ~end=8,
    ),
    made,
  )
  ok(made != Filling.bytes(~description="d", ~step=1, ~path="content", 8))
  ok(made != Filling.bytes(~description="d", ~step=0, ~path="name", 8))
  ok(made != Filling.bytes(~description="e", ~step=0, ~path="content", 8))
  deepEqual(TypedArray.length(Filling.bytes(~description="d", ~step=0, ~path="a", 0)), 0)
})

test("each placeholder of an input is made, at its path", () => {
  let filled = Filling.fill(
    parse(`{
      "to": {"$use": "address"},
      "at": {"$time": {"ago": 60000}},
      "content": {"$bytes": {"length": {"bound": "content", "plus": 1}}},
      "statements": [{"sql": {"$text": {"start": "SELECT 1", "length": 12}}}],
      "version": {"$fixture": "echo-modules"},
      "kept": [1, "a", null]
    }`),
    context,
  )
  let content = Filling.bytes(~description=context.description, ~step=2, ~path="content", 9)
  deepEqual(
    filled,
    Ok(
      JSON.Object(
        dict{
          "to": JSON.String("http://localhost:8787"),
          "at": JSON.Number(1_799_999_940_000.),
          "content": JSON.String(Web.base64url(content)),
          "statements": JSON.Array([JSON.Object(dict{"sql": JSON.String("SELECT 1    ")})]),
          "version": JSON.String(String.repeat("ab", 32)),
          "kept": parse(`[1, "a", null]`),
        },
      ),
    ),
  )
  // A value's path runs through a list by its index.
  switch Filling.fill(parse(`[{"a": {"$bytes": {"length": 4}}}]`), context) {
  | Ok(json) =>
    deepEqual(
      json,
      parse(
        `[{"a": "${Filling.bytes(
            ~description=context.description,
            ~step=2,
            ~path="0/a",
            4,
          )->Web.base64url}"}]`,
      ),
    )
  | Error(_) => ok(false)
  }
})

test(
  "what the run does not offer is refused as not offered, and a placeholder not as written as unwritten",
  () => {
    deepEqual(
      Filling.fill(parse(`{"$bytes": {"length": {"bound": "statement", "plus": 0}}}`), context),
      Error(Unoffered("the bound statement, which the run is given no value of")),
    )
    deepEqual(
      Filling.fill(parse(`{"$fixture": "echo-image"}`), context),
      Error(Unoffered("the fixture echo-image, which the run builds none of")),
    )
    ok(
      switch Filling.fill(parse(`{"wal": {"$frames": {"writes": ["INSERT"]}}}`), context) {
      | Error(Unoffered(_)) => true
      | Ok(_) | Error(Unwritten(_)) => false
      },
    )
    deepEqual(
      Filling.fill(parse(`{"$use": "none"}`), context),
      Error(Unwritten(`$use "none", captured by no step before`)),
    )
    deepEqual(
      Filling.fill(parse(`{"$later": 1}`), context),
      Error(Unwritten("$later, no placeholder an input is made by")),
    )
  },
)
