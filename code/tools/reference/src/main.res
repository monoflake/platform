let main = async () =>
  switch Target.parse(Conform.Host.argv->Array.slice(~start=2)) {
  | Error(why) =>
    Console.error(`reference: ${why}`)
    Conform.Host.setExitCode(Conform.Host.process, 2)
  | Ok((target, dry)) =>
    let report = await Steps.run(
      ~machine=Machine.make(target),
      ~unique=Process.unique(),
      ~dry,
      ~say=Console.log,
    )
    if !dry {
      report.app->Option.forEach(id => {
        Console.log(`reference: app ${Ids.Id.text(id)} left in place`)
        Console.error(
          `reference: remove with mise run retire ${Target.name(target)} --app ${Ids.Id.text(id)}`,
        )
      })
    }
    if report.failed != None {
      Conform.Host.setExitCode(Conform.Host.process, 1)
    }
  }

let _ = main()->Promise.catch(error => {
  let why = switch error {
  | JsExn(error) => error->JsExn.message->Option.getOr("unexpected failure")
  | _ => "unexpected failure"
  }
  Console.error(`reference: ${why}`)
  Conform.Host.setExitCode(Conform.Host.process, 1)
  Promise.resolve()
})
