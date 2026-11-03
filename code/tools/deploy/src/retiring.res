module Contracts = Envelope.Contracts

let phase = (name, run, said) => {
  let started = Date.now()
  let result = run()
  let took = ((Date.now() -. started) /. 1000.)->Float.toFixed(~digits=1)
  switch result {
  | Ok(value) => Console.log(`deploy: ${name} ${took}s, ${said(value)}`)
  | Error(why) => Console.error(`deploy: ${name} failed after ${took}s, ${why}`)
  }
  result
}

let run = (~app, ~dry, ~ask) => {
  let call = (call, data) =>
    ask(Contracts.Interface.Deployments.toJson({call, capabilities: []}))
    ->Result.mapError((message): Machine.refused => {reason: "unreached", message})
    ->Result.flatMap(text => Machine.answer(text, data))
  let refusal = ({reason, message}: Machine.refused) => `${reason}: ${message}`
  let of_ = Deploying.of_(app)
  phase(
    "describe",
    () =>
      switch call(Describe(of_), Contracts.DeploymentDescribed.fromJson) {
      | Ok(described) => Ok(Some(described.version))
      | Error({reason: "not_found"}) => Ok(None)
      | Error(refused) => Error(refusal(refused))
      },
    version =>
      switch version {
      | Some(version) => `app ${Ids.Id.text(app)}, version ${Envelope.Hex.encode(version)}`
      | None => `app ${Ids.Id.text(app)} is not there`
      },
  )->Result.flatMap(version =>
    switch version {
    | None => Ok()
    | Some(_) =>
      let step = (name, call_, data, said) =>
        phase(
          name,
          () => dry ? Ok() : call(call_, data)->Result.mapError(refusal)->Result.map(_ => ()),
          () => `app ${Ids.Id.text(app)} ${dry ? "would be " : ""}${said}`,
        )
      step(
        "stop",
        Stop(of_),
        Contracts.DeploymentDescribed.fromJson,
        "stopped",
      )->Result.flatMap(() =>
        step("delete", Delete(of_), Contracts.DeploymentDeleted.fromJson, "deleted")
      )
    }
  )
}
