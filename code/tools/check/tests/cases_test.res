/*** The samples' check of a case's `network`, a step's `as` and its `bearer`, RFC 8j7b0. */
open Testing

let parse = JSON.parseOrThrow

let scope = (~captured): Cases.scope => {
  found: [],
  captured: Set.fromArray(captured),
  bounds: dict{},
  declared: [],
  fixtures: [],
}

test("a case's network and tunnel are true or false where they are written", () => {
  let found = []
  [
    "{}",
    `{"network": true, "tunnel": false}`,
    `{"network": "yes"}`,
    `{"tunnel": 1}`,
    `{"tunnel": "yes", "network": null}`,
  ]->Array.forEachWithIndex((c, i) =>
    ["network", "tunnel"]->Array.forEach(
      name => Cases.marked(found, parse(c), Int.toString(i), name),
    )
  )
  deepEqual(
    found,
    [
      "2: network, true or false",
      "3: tunnel, true or false",
      "4: network, true or false",
      "4: tunnel, true or false",
    ],
  )
})

/** An operation of the model by its interface and name. */
let operationOf = (interface, name) =>
  switch Contracts.interfaces
  ->Array.find(i => i.name == interface)
  ->Option.flatMap(i => i.operations->Array.find(o => o.name == name)) {
  | Some(o) => o
  | None => JsError.throwWithMessage(`no ${interface} ${name}`)
  }

test("a step is called as the operator only where the model's callers name it", () => {
  let found = []
  [
    ("bindings", "open", `{"as": "operator"}`),
    ("organizations", "open", `{}`),
    ("bindings", "bind", `{"as": "operator"}`),
    ("object", "read", `{"as": "operator"}`),
    ("bindings", "open", `{"as": "admin"}`),
    ("bindings", "open", `{"as": 1}`),
    ("bindings", "open", `{"as": "operator", "bearer": {"$use": "opened"}}`),
  ]->Array.forEachWithIndex(((interface, name, st), i) =>
    Cases.caller(
      found,
      ~interface,
      ~operation=operationOf(interface, name),
      parse(st),
      Int.toString(i),
    )
  )
  deepEqual(
    found,
    [
      "2: as the operator, on bind, which is not the operator's",
      "3: as the operator, on read, which is not the operator's",
      "4: as, a component to a component or the operator to its own operation",
      "5: as, a component to a component or the operator to its own operation",
      "6: as the operator and a bearer at once",
    ],
  )
})

test("a bearer is one $use of a name captured before, and nothing else", () => {
  let s = scope(~captured=["organization", "opened"])
  [
    `{}`,
    `{"bearer": {"$use": "opened"}}`,
    `{"bearer": {"$use": "later"}}`,
    `{"bearer": "opened"}`,
    `{"bearer": {"$use": "opened", "and": 1}}`,
    `{"bearer": {"$capture": "opened"}}`,
    `{"bearer": {"$use": 1}}`,
    `{"bearer": {"$use": "organization"}}`,
  ]->Array.forEachWithIndex((st, i) => Cases.bearer(s, parse(st), Int.toString(i)))
  deepEqual(
    s.found,
    [
      "2: bearer uses later, captured by no step before",
      `3: bearer, {"$use": name} alone`,
      `4: bearer, {"$use": name} alone`,
      `5: bearer, {"$use": name} alone`,
      `6: bearer, {"$use": name} alone`,
      "7: bearer uses organization, which is no binding's token",
    ],
  )
})

test("every case begins with the run's organization captured", () =>
  deepEqual(Cases.capturedFirst, ["organization"])
)

test("a case binding by a tunnel is refused unless it is marked tunnel true", () => {
  let found = []
  let step = `{"call": "bind", "input": {"reach": {"name": "tunnel"}}, "expect": {"output": {}}}`
  let origin = `{"call": "bind", "input": {"reach": {"name": "origin", "origin": "https://example.com"}}, "expect": {"output": {}}}`
  [
    ("bindings", `{"steps": [${step}]}`),
    ("bindings", `{"tunnel": true, "steps": [${step}]}`),
    ("bindings", `{"tunnel": false, "steps": [${step}]}`),
    ("bindings", `{"steps": [${origin}]}`),
    ("object", `{"steps": [${step}]}`),
  ]->Array.forEachWithIndex(((interface, c), i) =>
    Cases.tunneling(found, ~interface, parse(c), Int.toString(i))
  )
  deepEqual(
    found,
    [
      "0: binds by a tunnel, which only a case marked tunnel true may",
      "2: binds by a tunnel, which only a case marked tunnel true may",
    ],
  )
})
