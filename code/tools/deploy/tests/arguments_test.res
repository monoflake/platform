/***
 * `Arguments` held to RFC b8f35, a deploy's, a forget's and a retire's arguments, each id 8 hex
 * digits.
 */
open Node

let deploy: Arguments.t = {
  directory: "apps/hello",
  target: "control:https://c.example",
  app: None,
  binding: None,
  forget: None,
  retire: None,
  secrets: [],
  network: [],
  ingress: None,
  dry: false,
}

test("ingress flags parse each kind and keep the order given", () => {
  deepEqual(
    Arguments.parse([
      "apps/hello",
      "local",
      "--ingress",
      "domain:example.com",
      "--ingress",
      "mount:hello",
      "--dry-run",
      "--ingress",
      "binding",
      "--ingress",
      "domain:*.example.org",
    ]),
    Ok({
      ...deploy,
      target: "local",
      ingress: Some([
        Domain({domain: "example.com"}),
        Mount({scope: "hello"}),
        Binding,
        Domain({domain: "*.example.org"}),
      ]),
      dry: true,
    }),
  )
})

test("malformed ingress is refused by name before a build", () => {
  [
    "",
    "domain:",
    "domain:Example.com",
    "domain:example.com.",
    "domain:example..com",
    "domain:example.123",
    "domain:*.example.*.org",
    "domain:*.*.example.org",
    "domain:example.com/path",
    "domain:https://example.com",
    "domain:-app.example.com",
    "domain:app-.example.com",
    "domain:app_name.example.com",
    "domain:" ++ String.repeat("a", 64) ++ ".example.com",
    "domain:" ++ String.repeat("a.", 122) ++ "example.com",
    "mount:",
    "mount: ",
    "binding:",
    "binding:hello",
    "other:hello",
  ]->Array.forEach(text =>
    deepEqual(
      Arguments.parse(["apps/hello", "local", "--ingress", text]),
      Error(`--ingress ${text} is no domain:<name>, mount:<scope> or binding`),
    )
  )
  ok(Arguments.parse(["apps/hello", "local", "--ingress"])->Result.isError)
})

test("forget and retire refuse ingress as they refuse other deploy flags", () =>
  ["forget", "retire"]->Array.forEach(flag =>
    deepEqual(
      Arguments.parse([
        "control:https://control.example.net",
        "--" ++ flag,
        "00000001",
        "--ingress",
        "binding",
      ]),
      Error(`--${flag} takes the control's target alone, and --dry-run`),
    )
  )
)

test("a deploy's app and binding are 8 lowercase hex digits, and nothing else", () => {
  deepEqual(
    Arguments.parse([
      "apps/hello",
      "control:https://c.example",
      "--binding",
      "00000001",
      "--app",
      "0a1b2c3d",
      "--network",
      "http,tcp",
      "--dry-run",
    ]),
    Ok({
      ...deploy,
      app: Some(169552957.),
      binding: Some(1.),
      network: [Http, Tcp],
      dry: true,
    }),
  )
  ok(Arguments.parse(["apps/hello", "control:https://c.example", "--binding", "1"])->Result.isError)
  ok(Arguments.parse(["apps/hello", "local", "--app", "app-2"])->Result.isError)
  ok(Arguments.parse(["apps/hello"])->Result.isError)
})

test("a forget takes a control's target alone, its app 8 hex digits", () => {
  deepEqual(
    Arguments.parse(["control:https://c.example", "--forget", "0a1b2c3d"]),
    Ok({...deploy, directory: "", forget: Some(169552957.)}),
  )
  deepEqual(
    Arguments.parse(["--forget", "0a1b2c3d", "control:https://c.example", "--dry-run"]),
    Ok({...deploy, directory: "", forget: Some(169552957.), dry: true}),
  )
  ok(Arguments.parse(["control:https://c.example", "--forget", "2"])->Result.isError)
  ok(Arguments.parse(["control:https://c.example", "--forget"])->Result.isError)
  ok(Arguments.parse(["--forget", "0a1b2c3d"])->Result.isError)
  ok(
    Arguments.parse([
      "apps/hello",
      "control:https://c.example",
      "--forget",
      "0a1b2c3d",
    ])->Result.isError,
  )
  ok(
    Arguments.parse([
      "control:https://c.example",
      "--forget",
      "0a1b2c3d",
      "--binding",
      "00000001",
    ])->Result.isError,
  )
})

test("a forget is refused to a machine ssh reaches, as only a control drew the id", () => {
  deepEqual(
    Arguments.parse(["root@machine.example", "--forget", "0a1b2c3d"]),
    Error("--forget asks a control, and root@machine.example is a machine ssh reaches"),
  )
  ok(Arguments.parse(["local", "--forget", "0a1b2c3d"])->Result.isError)
})

test(
  "a retire takes a control's target alone, its app 8 hex digits, and never with a forget",
  () => {
    deepEqual(
      Arguments.parse(["control:https://c.example", "--retire", "00000001"]),
      Ok({...deploy, directory: "", retire: Some(1.)}),
    )
    deepEqual(
      Arguments.parse(["--retire", "0a1b2c3d", "control:https://c.example", "--dry-run"]),
      Ok({...deploy, directory: "", retire: Some(169552957.), dry: true}),
    )
    ok(Arguments.parse(["control:https://c.example", "--retire", "1"])->Result.isError)
    ok(Arguments.parse(["control:https://c.example", "--retire"])->Result.isError)
    ok(Arguments.parse(["--retire", "0a1b2c3d"])->Result.isError)
    ok(
      Arguments.parse([
        "apps/hello",
        "control:https://c.example",
        "--retire",
        "0a1b2c3d",
      ])->Result.isError,
    )
    deepEqual(
      Arguments.parse(["control:https://c.example", "--retire", "0a1b2c3d", "--app", "00000002"]),
      Error("--retire takes the control's target alone, and --dry-run"),
    )
    deepEqual(
      Arguments.parse(["root@machine.example", "--retire", "0a1b2c3d"]),
      Error("--retire asks a control, and root@machine.example is a machine ssh reaches"),
    )
    deepEqual(
      Arguments.parse([
        "control:https://c.example",
        "--retire",
        "0a1b2c3d",
        "--forget",
        "0a1b2c3e",
      ]),
      Error("--forget and --retire are two calls, made one at a time"),
    )
  },
)
