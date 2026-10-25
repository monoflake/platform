/*** `Arguments` held to RFC b8f35, a deploy's and a forget's arguments, each id 8 hex digits. */
open Node

let deploy: Arguments.t = {
  directory: "apps/hello",
  target: "control:https://c.example",
  app: None,
  binding: None,
  forget: None,
  secrets: [],
  network: [],
  dry: false,
}

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
