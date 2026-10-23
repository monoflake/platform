/***
 * A test machine's driver, entry and containerd restarted and a build copied in while hello is
 * asked through the entry and the tunnel, each request counted, RFC ehm48; only order is here.
 */
module Host = Conform.Host
module Live = Conform.Live
module Remote = Conform.Remote
module Run = Lose.Run

let usage = "replace <target> [--no-build | --during <command>] [--dry-run]"

/** The app whose deployment hello is, as deploy makes it. */
let app = 1

/** How long the load runs before the first action, and how long after each before the next. */
let warm = 1000.
let lead = 3000.
let pause = 5000.

/** The build copied in, as monoflake/driver's `dev` does it, its restarts included. */
let build = "a new build copied in by dev"

let say = line => Console.log(`replace: ${line}`)
let seconds = ms => (ms /. 1000.)->Float.toFixed(~digits=1)

/** A command run on the machine, what it wrote, or why it failed. */
let remote = async (target: Remote.target, command) => {
  let {code, stdout, stderr}: Run.ran = await Run.run(
    "ssh",
    [...target.options, target.host, command],
  )
  code == 0 ? Ok(stdout) : Error(`${stderr->String.trim} ${stdout->String.trim}`->String.trim)
}

/** A command run on the machine and waited on, for a signal's handler that cannot wait. */
let remoteNow = (target: Remote.target, command) =>
  Host.spawnSync(
    "ssh",
    [...target.options, target.host, command],
    {stdio: ["ignore", "pipe", "pipe"], encoding: "utf8"},
  ).status->Nullable.toOption == Some(0)

/** One action's window, its name and when it began on the machine's clock and on this one. */
type phase = {name: string, there: float, here: float}

let marked = async (target, name) => {
  let here = Date.now()
  switch (await remote(target, Actions.clock))->Result.map(String.trim) {
  | Ok(text) =>
    Float.fromString(text)->Option.mapOr(Error(`the machine's clock read ${text}`), there => Ok({
      name,
      there,
      here,
    }))
  | Error(why) => Error(`the machine's clock not read, ${why}`)
  }
}

/** hello asked once through the tunnel, from here. */
let askedTunnel = async address => {
  let began = Date.now()
  let outcome = switch await Host.fetchWithin(address, 10000) {
  | response => Load.fetched(~status=response->Host.status, ~body=await response->Host.text)
  | exception JsExn(e) =>
    Load.thrown(~code=Streamed.code(e), ~message=e->JsExn.message->Option.getOr("not reached"))
  }
  ({began, ended: Date.now(), outcome}: Load.asked)
}

/** `Load.clients` clients asking through the tunnel back to back until `stopped` is set. */
let tunnelLoad = (address, stopped: ref<bool>) =>
  Promise.all(
    Array.fromInitializer(~length=Load.clients, async _ => {
      let asks = []
      while !stopped.contents {
        asks->Array.push(await askedTunnel(address))
      }
      asks
    }),
  )->Promise.thenResolve(Array.flat)

/** Each check said, and whether all held. */
let told = (when_, checks) =>
  checks->Array.reduce(true, (held, (what, result)) =>
    switch result {
    | Ok() =>
      say(`${when_}, ${what}`)
      held
    | Error(why) =>
      say(`${when_}, failed: ${what}, ${why}`)
      false
    }
  )

/** Every unit active and hello answering once through each path. */
let looked = async (target, ~binding, ~tunnel, ~when_) => {
  let units = (await remote(target, Actions.states))->Result.flatMap(Actions.active)
  let entry =
    (await remote(target, Live.hello(~app, ~binding)))
    ->Result.flatMap(Live.readAnswered)
    ->Result.flatMap(Live.greeted)
  let through = switch tunnel {
  | None => []
  | Some(address) =>
    let {outcome} = await askedTunnel(address)
    [
      (
        "hello answers through the tunnel",
        switch outcome {
        | Answered => Ok()
        | Refused(why) | Failed(why) => Error(why)
        },
      ),
    ]
  }
  told(
    when_,
    [
      (`${Actions.units->Array.join(", ")} are active where the machine has them`, units),
      ("hello answers through the entry", entry),
      ...through,
    ],
  )
}

/** Where an action runs, a shell on the machine or a program here. */
type action = There(string) | Here(string, array<string>)

/** One action taken, a restart on the machine, or a build copied in or a command run here. */
let taken = async (target: Remote.target, (name, action)) =>
  switch action {
  | There(shell) => (await remote(target, shell))->Result.map(_ => ())
  | Here(program, args) =>
    let child = Host.spawn(program, args, {stdio: ["ignore", "inherit", "inherit"]})
    (await Host.ended(child)) == 0 ? Ok() : Error(`${name} failed`)
  }

/** The load started, each action taken in turn with a pause after it, and the load stopped. */
let replaced = async (target: Remote.target, ~binding, ~tunnel, ~stop, ~actions) => {
  let entry = Streamed.started(
    "ssh",
    [...target.options, target.host, Load.shell(~app, ~binding, ~stop)],
  )
  let stopped = ref(false)
  let tunneled = switch tunnel {
  | Some(address) => tunnelLoad(address, stopped)
  | None => Promise.resolve([])
  }
  await Host.sleep(Float.toInt(warm))
  let phases = []
  let done = []
  let failed = ref(None)
  switch await marked(target, "nothing done") {
  | Error(why) => failed := Some(why)
  | Ok(phase) =>
    phases->Array.push(phase)
    await Host.sleep(Float.toInt(lead))
  }
  for i in 0 to actions->Array.length - 1 {
    switch (failed.contents, actions->Array.get(i)) {
    | (None, Some((name, action))) =>
      switch await marked(target, name) {
      | Error(why) => failed := Some(why)
      | Ok(phase) =>
        phases->Array.push(phase)
        say(`${name}, under load`)
        let result = await taken(target, (name, action))
        done->Array.push((name, result))
        await Host.sleep(Float.toInt(pause))
      }
    | (Some(_), _) | (_, None) => ()
    }
  }
  let ending = await marked(target, "end")
  stopped := true
  let stoppedThere = await remote(target, `touch '${stop}'`)
  let (code, written) = await entry
  let tunnelAsks = await tunneled
  let entryAsks = written->String.split("\n")->Array.filterMap(Load.read)
  switch (failed.contents, ending, stoppedThere) {
  | (Some(why), _, _) => Error(why)
  | (None, Error(why), _) => Error(why)
  | (None, Ok(_), Error(why)) => Error(`the load not stopped, ${why}`)
  | (None, Ok(ending), Ok(_)) if code == 0 => Ok((phases, ending, done, entryAsks, tunnelAsks))
  | (None, Ok(_), Ok(_)) => Error(`the load on the machine ended ${Int.toString(code)}`)
  }
}

/** Each action's window counted on each path, said, and whether every one held. */
let reported = ((phases, ending: phase, done, entryAsks, tunnelAsks), ~tunnel) => {
  let held = ref(true)
  phases->Array.forEachWithIndex((phase: phase, i) => {
    let next = phases->Array.get(i + 1)->Option.getOr(ending)
    let paths = [
      Counted.count(~path="entry", ~from=phase.there, ~until=next.there, entryAsks),
      ...tunnel
        ? [Counted.count(~path="tunnel", ~from=phase.here, ~until=next.here, tunnelAsks)]
        : [],
    ]
    paths->Array.forEach(c => {
      say(`${phase.name}, ${Counted.line(c)}`)
      if !Counted.held(c) {
        held := false
      }
    })
  })
  done->Array.forEach(((name, result)) =>
    switch result {
    | Ok() => ()
    | Error(why) =>
      say(`failed: ${name}, ${why}`)
      held := false
    }
  )
  held.contents
}

let main = async () => {
  let started = Date.now()
  let took = () => seconds(Date.now() -. started)
  let args = Host.argv->Array.slice(~start=2)
  let dry = args->Array.includes("--dry-run")
  let building = !(args->Array.includes("--no-build"))
  let (during, args) = switch args->Array.findIndex(a => a == "--during") {
  | -1 => (None, args)
  | at => (args->Array.get(at + 1), args->Array.filterWithIndex((_, i) => i != at && i != at + 1))
  }
  let known = ["--dry-run", "--no-build"]
  let flags = args->Array.filter(a => a->String.startsWith("--"))
  switch args->Array.filter(a => !(a->String.startsWith("--"))) {
  | [named] if flags->Array.every(f => known->Array.includes(f)) =>
    let target = Remote.target(named)
    let binding =
      (await remote(target, Live.binding))->Result.flatMap(text =>
        Int.fromString(text->String.trim)->Option.mapOr(Error(`${text} is no id`), id => Ok(id))
      )
    switch binding {
    | Error(why) =>
      say(`failed: the live binding of ${named} was not read, ${why}`)
      Host.setExitCode(Host.process, 1)
    | Ok(binding) =>
      let tunnel = switch (await remote(target, Live.tunnel))->Result.map(String.trim) {
      | Ok("") | Error(_) => None
      | Ok(address) => Some(address)
      }
      let dev = Here("mise", ["run", "//repos/monoflake/driver:dev", named])
      let actions = switch during {
      | Some(command) => [(command, Here("sh", ["-c", command]))]
      | None =>
        [
          ...Actions.restarts->Array.map(a => (a.name, There(a.shell))),
          ...building ? [(build, dev)] : [],
        ]
      }
      let names = actions->Array.map(((name, _)) => name)->Array.join(", then ")
      let through = tunnel->Option.isSome ? "the entry and the tunnel" : "the entry"
      if !(await looked(target, ~binding, ~tunnel, ~when_="before")) {
        say(`${named} does not serve as it should, so nothing is replaced, ${took()}s`)
        Host.setExitCode(Host.process, 1)
      } else if dry {
        say(`would ask hello through ${through}, ${Int.toString(Load.clients)} clients on each`)
        say(`would ${names}, ${seconds(pause)}s apart, and count each one's requests`)
        say(`nothing replaced, as --dry-run asks, ${took()}s`)
      } else {
        let stop = `/tmp/replace-${Float.toString(started)}`
        ["SIGINT", "SIGTERM", "SIGHUP"]->Array.forEach(signal =>
          Host.onSignal(Host.process, signal, () => {
            let back = remoteNow(target, `touch '${stop}'; ${Actions.kept}`)
            say(back ? "every unit started again" : "failed: a unit did not start")
            Host.exit(Host.process, 130)
          })
        )
        say(`hello asked through ${through}, ${Int.toString(Load.clients)} clients on each`)
        let run = try await replaced(target, ~binding, ~tunnel, ~stop, ~actions) catch {
        | JsExn(e) => Error(e->JsExn.message->Option.getOr("the run threw"))
        }
        let back =
          (await remote(target, Actions.kept))->Result.isOk || remoteNow(target, Actions.kept)
        let kept = switch run {
        | Ok(window) => reported(window, ~tunnel=tunnel->Option.isSome)
        | Error(why) =>
          remoteNow(target, `touch '${stop}'`)->ignore
          say(`failed: ${why}`)
          false
        }
        let still = await looked(target, ~binding, ~tunnel, ~when_="after")
        let met = kept && back && still
        say(
          `${named} ${met
              ? "refuses and fails nothing while it is replaced"
              : "does not serve every request while it is replaced"}, ${took()}s`,
        )
        Host.setExitCode(Host.process, met ? 0 : 1)
      }
    }
  | _ =>
    Console.error(`replace: ${usage}`)
    Host.setExitCode(Host.process, 2)
  }
}

await main()
