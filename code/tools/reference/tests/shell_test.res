open Node

test("deploy runs as a program and only the second deployment supplies the app id", async () => {
  let target = Target.Machine("local")
  equal(
    Shell.deployArgs(~directory="code/tools/reference", ~target, ~app=None, ~dry=false),
    ["code/tools/deploy/src/main.res.mjs", "code/tools/reference", "local"],
  )
  equal(
    Shell.deployArgs(~directory="code/tools/reference", ~target, ~app=Some(42.), ~dry=false),
    ["code/tools/deploy/src/main.res.mjs", "code/tools/reference", "local", "--app", "0000002a"],
  )
  equal(
    Shell.deployArgs(~directory="code/tools/reference", ~target, ~app=None, ~dry=true),
    ["code/tools/deploy/src/main.res.mjs", "code/tools/reference", "local", "--dry-run"],
  )
})

test(
  "the final deploy line names the app and early drawing remains available on failure",
  async () => {
    equal(Shell.app("deploy: app 0000002a\n"), Some(42.))
    equal(Shell.app("deploy: app 0.1s, 0000002a, drawn, as no control draws it\n"), None)
    equal(Shell.drawn("deploy: app 0.1s, 0000002a, drawn, as no control draws it\n"), Some(42.))
    equal(Shell.app("deploy: app nope\n"), None)
  },
)

test("entry requests reuse conform's entry discovery, host and response framing", async () => {
  let command = Shell.request(
    ~app=42.,
    ~binding=3.,
    {method: "PUT", path: "/row/reference", body: Some("value")},
  )
  ok(command->String.startsWith(Conform.Live.entered))
  ok(command->String.includes("Host: 0000002a.b00000003"))
  ok(command->String.includes("--data-binary @-"))
  ok(command->String.includes("http://$e/row/reference"))
  equal(
    Conform.Live.readAnswered("value\n\n200\n"),
    Ok(({status: 200, body: "value\n"}: Conform.Live.answered)),
  )
})

test("target parsing accepts only a machine and optional dry run", async () => {
  equal(Target.parse(["local", "--dry-run"]), Ok((Target.Machine("local"), true)))
  [
    [],
    ["https://control.invalid"],
    ["--bad"],
    ["local", "--app", "0000002a"],
  ]->Array.forEach(args => {
    ok(Target.parse(args)->Result.isError)
  })
})
