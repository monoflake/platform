type event = Deploy(option<float>, string, bool) | Ask(float, Steps.request)

let machine = (~fail=None, ~wrong=None, ~status=501, ~stale=false, ~otherApp=false, ()) => {
  let events = []
  let lines = []
  let deployed = ref(false)
  let stamp = ref("")
  let asks = ref(0)
  let row = ref("")
  let object = ref("")
  let deploy = async (~app, ~stamp as nextStamp, ~dry) => {
    events->Array.push(Deploy(app, nextStamp, dry))
    let name = deployed.contents ? "redeployed" : "deployed"
    if !deployed.contents || !stale {
      stamp := nextStamp
    }
    deployed := true

    (
      {
        app: Some(otherApp && name == "redeployed" ? 43. : 42.),
        status: fail == Some(name) ? 1 : 0,
        body: "deploy: app 0000002a\n",
      }: Steps.deployment
    )
  }
  let ask = async (app, request: Steps.request) => {
    events->Array.push(Ask(app, request))
    let name =
      [
        "answers",
        "row written",
        "object stored",
        "row read back",
        "object read back",
        "redeployed",
        "row kept",
        "object kept",
      ]
      ->Array.get(asks.contents)
      ->Option.getOr("unexpected request")
    asks := asks.contents + 1
    if fail == Some(name) {
      ({status, body: "no binding reaches database, RFC rt6gi"}: Steps.observation)
    } else {
      let body = switch (request.method, request.path) {
      | ("GET", "/") => Handler.greeting(stamp.contents)
      | ("PUT", "/row/reference") =>
        row := request.body->Option.getOr("")
        "written"
      | ("PUT", "/object/reference") =>
        object := request.body->Option.getOr("")
        "stored"
      | ("GET", "/row/reference") => row.contents
      | ("GET", "/object/reference") => object.contents
      | _ => "unexpected request"
      }
      ({status: 200, body: wrong == Some(name) ? body ++ "changed" : body}: Steps.observation)
    }
  }
  (({deploy, ask}: Steps.machine), events, lines)
}

let run = async (
  ~fail=?,
  ~wrong=?,
  ~status=?,
  ~stale=?,
  ~otherApp=?,
  ~dry=false,
  ~unique="run",
  (),
) => {
  let (machine, events, lines) = machine(~fail?, ~wrong?, ~status?, ~stale?, ~otherApp?, ())
  let report = await Steps.run(~machine, ~unique, ~dry, ~say=line => lines->Array.push(line))
  (report, events, lines)
}
