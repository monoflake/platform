/***
 * `Sample.read` held to the samples as they stand, every behavior file read and the properties
 * refused.
 */
open Node

let behavior = Array.concatMany(
  files("tests/kinds"),
  [files("tests/products"), files("tests/components")],
)

test("every behavior file in tests/ reads, each with its cases", () => {
  ok(behavior->Array.length > 0, ~message="no behavior files")
  behavior->Array.forEach(path =>
    switch Sample.read(readFileSync(fromRoot(path))) {
    | Ok(file) =>
      ok(file.interface != "", ~message=`${path}: no interface`)
      ok(file.cases->Array.length > 0, ~message=`${path}: no cases`)
      file.cases->Array.forEach(
        c => ok(c.steps->Array.length > 0, ~message=`${path}: ${c.description}`),
      )
    | Error(why) => ok(false, ~message=`${path}: ${why}`)
    }
  )
})

test("a property is no behavior file", () => {
  let properties = files("tests/properties")
  ok(properties->Array.length > 0, ~message="no properties")
  properties->Array.forEach(path =>
    ok(Sample.read(readFileSync(fromRoot(path)))->Result.isError, ~message=path)
  )
})

let one = text =>
  switch Sample.read(text) {
  | Ok({cases: [{steps}]}) => steps
  | Ok(_) => JsError.throwWithMessage("not one case")
  | Error(why) => JsError.throwWithMessage(why)
  }

test("each form of a step is read, and what a step leaves out is none", () => {
  let steps = one(`{"interface": "object", "cases": [{"description": "d", "steps": [
    {"call": "write", "input": {"name": "a"}, "expect": {"output": {}}, "within": 500, "as": "compute"},
    {"call": "deploy", "fixture": "echo-modules", "expect": {"failure": "rejected", "reason": "denied"}},
    {"send": {"to": {"$use": "address"}, "export": "echo", "key": "k", "body": {"text": "a"}}, "expect": {"answer": {"text": "a"}}},
    {"lose": 1},
    {"wait": 1000}
  ]}]}`)
  deepEqual(
    steps,
    [
      Call({
        operation: "write",
        input: JSON.Object(dict{"name": JSON.String("a")}),
        expect: Output(JSON.Object(dict{})),
        within: Some(500),
        as_: Some("compute"),
        bearer: None,
        fixture: None,
      }),
      Call({
        operation: "deploy",
        input: JSON.Null,
        expect: Failure({failure: "rejected", reason: "denied"}),
        within: None,
        as_: None,
        bearer: None,
        fixture: Some("echo-modules"),
      }),
      Send({
        send: {
          to: JSON.Object(dict{"$use": JSON.String("address")}),
          export: "echo",
          key: Some("k"),
          body: Some(JSON.Object(dict{"text": JSON.String("a")})),
        },
        expect: Answer(JSON.Object(dict{"text": JSON.String("a")})),
        within: None,
      }),
      Lose(1),
      Wait(1000),
    ],
  )
})

test("a case's given and copies are read, and a key no reader knows passed over", () => {
  switch Sample.read(`{"interface": "database", "later": 1, "cases": [{"description": "d", "given": {"size": 1}, "copies": 3, "steps": [{"wait": 1}]}]}`) {
  | Ok({cases: [c]}) =>
    deepEqual(c.given, Some(JSON.Object(dict{"size": JSON.Number(1.)})))
    deepEqual(c.copies, Some(3))
  | Ok(_) | Error(_) => ok(false)
  }
})

test("what is no behavior file is refused, saying where", () => {
  deepEqual(
    Sample.read("{"),
    Error("no JSON: Expected property name or '}' in JSON at position 1 (line 1 column 2)"),
  )
  deepEqual(Sample.read(`{"cases": []}`), Error("interface: absent"))
  deepEqual(
    Sample.read(`{"interface": "object", "cases": [{"description": "d", "steps": [{"input": {}}]}]}`),
    Error("cases/0/steps/0/neither a call, a send, a lose nor a wait"),
  )
  deepEqual(
    Sample.read(`{"interface": "object", "cases": [{"description": "d", "steps": [{"call": "read", "expect": {}}]}]}`),
    Error("cases/0/steps/0/expect: neither an output, an answer nor a failure"),
  )
  deepEqual(
    Sample.read(`{"interface": "object", "cases": [{"description": "d", "steps": [{"wait": -1}]}]}`),
    Error("cases/0/steps/0/wait: not a whole number"),
  )
})

test("a case needing the network and a step's bearer are read, and none where absent", () => {
  switch Sample.read(`{"interface": "bindings", "cases": [
    {"description": "d", "network": true, "tunnel": true, "steps": [
      {"call": "bind", "bearer": {"$use": "opened"}, "input": {}, "expect": {"output": {}}}
    ]},
    {"description": "e", "steps": [{"call": "open", "as": "operator", "input": {}, "expect": {"output": {}}}]}
  ]}`) {
  | Ok({cases: [first, second]}) =>
    deepEqual(
      (first.network && first.tunnel, first.steps, second.network || second.tunnel),
      (
        true,
        [
          Sample.Call({
            operation: "bind",
            input: JSON.Object(dict{}),
            expect: Output(JSON.Object(dict{})),
            within: None,
            as_: None,
            bearer: Some("opened"),
            fixture: None,
          }),
        ],
        false,
      ),
    )
  | Ok(_) | Error(_) => ok(false, ~message="not two cases")
  }
})

test("a network not a boolean, or a bearer not one $use of a name, is refused", () => {
  let read = (network, bearer) =>
    Sample.read(
      `{"interface": "bindings", "cases": [{"description": "d", ${network}"steps": [
      {"call": "bind", "bearer": ${bearer}, "input": {}, "expect": {"output": {}}}
    ]}]}`,
    )
  deepEqual(
    [
      read(`"network": "yes", `, `{"$use": "opened"}`),
      read(`"tunnel": 1, `, `{"$use": "opened"}`),
      read("", `"opened"`),
      read("", `{"$use": 1}`),
      read("", `{"$use": "opened", "and": 1}`),
      read("", `{"$capture": "opened"}`),
    ]->Array.map(r =>
      switch r {
      | Ok(_) => "read"
      | Error(why) => why
      }
    ),
    [
      "cases/0/network: not a boolean",
      "cases/0/tunnel: not a boolean",
      `cases/0/steps/0/bearer: not {"$use": name}`,
      "cases/0/steps/0/bearer: a $use names a capture",
      `cases/0/steps/0/bearer: not {"$use": name}`,
      `cases/0/steps/0/bearer: not {"$use": name}`,
    ],
  )
})
