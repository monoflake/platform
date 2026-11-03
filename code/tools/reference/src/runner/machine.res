module Host = Conform.Host

let directory = "code/tools/reference"

let stamped = stamp => {
  let generated = Host.fromRoot(`${directory}/generated`)
  Host.mkdir(generated, {recursive: true})
  Host.writeText(
    `${generated}/stamp.mjs`,
    `export const value = ${JSON.stringify(JSON.String(stamp))};\n`,
  )
}

let ssh = (target, command, ~input=?) => Process.run("ssh", Shell.remote(target, command), ~input?)

let make = target => {
  let facts = ref(None)
  let binding = async () =>
    switch facts.contents {
    | Some(binding) => Ok(binding)
    | None =>
      let ran = await ssh(target, Conform.Instance.facts)
      if ran.status != 0 {
        Error(({status: ran.status, body: ran.stderr ++ ran.stdout}: Steps.observation))
      } else {
        switch Conform.Instance.readFacts(ran.stdout, ~count=0) {
        | Ok({binding}) =>
          facts := Some(binding)
          Ok(binding)
        | Error(why) => Error({status: 0, body: why})
        }
      }
    }
  let deploy = async (~app, ~stamp, ~dry) => {
    stamped(stamp)
    let ran = await Process.run(Host.execPath, Shell.deployArgs(~directory, ~target, ~app, ~dry))
    let printed = Shell.app(ran.stdout)
    let id = printed == None ? Shell.drawn(ran.stdout) : printed
    ({app: id, status: ran.status, body: ran.stdout ++ ran.stderr}: Steps.deployment)
  }
  let ask = async (app, request: Steps.request) =>
    switch await binding() {
    | Error(answer) => answer
    | Ok(binding) =>
      let command =
        request == {method: "GET", path: "/", body: None}
          ? Conform.Live.hello(~app, ~binding)
          : Shell.request(~app, ~binding, request)
      let ran = await ssh(target, command, ~input=?request.body)
      if ran.status != 0 {
        ({status: 0, body: ran.stderr ++ ran.stdout}: Steps.observation)
      } else {
        switch Conform.Live.readAnswered(ran.stdout) {
        | Ok({status, body}) => {status, body}
        | Error(why) => {status: 0, body: why}
        }
      }
    }
  ({deploy, ask}: Steps.machine)
}
