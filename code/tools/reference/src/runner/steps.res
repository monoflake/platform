type request = {method: string, path: string, body: option<string>}
type deployment = {app: option<float>, status: int, body: string}
type observation = {status: int, body: string}
type machine = {
  deploy: (~app: option<float>, ~stamp: string, ~dry: bool) => promise<deployment>,
  ask: (float, request) => promise<observation>,
}
type report = {
  app: option<float>,
  failed: option<string>,
  notRun: array<string>,
}

let names = [
  "deployed",
  "answers",
  "row written",
  "object stored",
  "row read back",
  "object read back",
  "redeployed",
  "row kept",
  "object kept",
]

let payloads = unique => (`row ${unique}\n`, `object ${unique}\n`)

let run = async (~machine, ~unique, ~dry, ~say) => {
  let app = ref(None)
  let failed = ref(None)
  let notRun = ref([])
  let firstStamp = `${unique}-first`
  let secondStamp = `${unique}-second`
  let (row, object) = payloads(unique)
  let step = async (name, run) => {
    switch failed.contents {
    | Some(_) => notRun := [...notRun.contents, name]
    | None =>
      let (held, {status, body}) = try await run() catch {
      | JsExn(error) => (
          false,
          {status: 0, body: error->JsExn.message->Option.getOr("unexpected failure")},
        )
      }
      say(
        `reference: ${name} ${held ? "passed" : "failed"}, status ${Int.toString(
            status,
          )}, body ${JSON.stringify(JSON.String(body))}`,
      )
      if !held {
        failed := Some(name)
      }
    }
  }
  let deployed = async (~again) => {
    let stamp = again ? secondStamp : firstStamp
    let deployed = await machine.deploy(~app=again ? app.contents : None, ~stamp, ~dry)
    let previous = app.contents
    if !again {
      app := deployed.app
      deployed.app->Option.forEach(id => say(`reference: app ${Ids.Id.text(id)}`))
    }
    let held = deployed.status == 0 && deployed.app != None && (!again || deployed.app == previous)
    if held && again {
      switch app.contents {
      | Some(id) =>
        let answer = await machine.ask(id, {method: "GET", path: "/", body: None})
        (answer.status == 200 && answer.body == Handler.greeting(stamp), answer)
      | None => (false, {status: deployed.status, body: deployed.body})
      }
    } else {
      (held, {status: deployed.status, body: deployed.body})
    }
  }
  let asked = async (~method, ~path, ~body=None, ~expected=None) =>
    switch app.contents {
    | None => (false, {status: 0, body: "deploy printed no app id"})
    | Some(id) =>
      let answer = await machine.ask(id, {method, path, body})
      let held =
        (method == "GET" ? answer.status == 200 : answer.status >= 200 && answer.status < 300) &&
        expected->Option.mapOr(true, expected => answer.body == expected)
      (held, answer)
    }
  await step("deployed", () => deployed(~again=false))
  if !dry {
    await step("answers", () =>
      asked(~method="GET", ~path="/", ~expected=Some(Handler.greeting(firstStamp)))
    )
    await step("row written", () => asked(~method="PUT", ~path="/row/reference", ~body=Some(row)))
    await step("object stored", () =>
      asked(~method="PUT", ~path="/object/reference", ~body=Some(object))
    )
    await step("row read back", () =>
      asked(~method="GET", ~path="/row/reference", ~expected=Some(row))
    )
    await step("object read back", () =>
      asked(~method="GET", ~path="/object/reference", ~expected=Some(object))
    )
    await step("redeployed", () => deployed(~again=true))
    await step("row kept", () => asked(~method="GET", ~path="/row/reference", ~expected=Some(row)))
    await step("object kept", () =>
      asked(~method="GET", ~path="/object/reference", ~expected=Some(object))
    )
  } else if failed.contents == None {
    say("reference: dry run, deploy built the Worker and asked the machine; nothing deployed")
  }
  if notRun.contents != [] {
    say(`reference: did not run ${notRun.contents->Array.join(", ")}`)
  }
  {app: app.contents, failed: failed.contents, notRun: notRun.contents}
}
