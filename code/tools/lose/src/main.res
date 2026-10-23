/***
 * A test machine's driver stopped while hello is asked through the entry and the tunnel, its calls
 * found refused, and the driver started again and found as it was, RFC rmll5; only order is here.
 */
module Contracts = Envelope.Contracts
module Host = Conform.Host
module Live = Conform.Live
module Remote = Conform.Remote

let usage = "lose <target> [--dry-run]"

/** The app whose deployment hello is, as deploy makes it. */
let app = 1

/** How long the driver is kept stopped, and how often each path is asked meanwhile. */
let window = 20000.
let every = 500.

let say = line => Console.log(`lose: ${line}`)
let seconds = ms => (ms /. 1000.)->Float.toFixed(~digits=1)

/** A command run on the machine, what it wrote, or why it failed. */
let remote = async (target: Remote.target, command) => {
  let {code, stdout, stderr}: Run.ran = await Run.run(
    "ssh",
    [...target.options, target.host, command],
  )
  code == 0 ? Ok(stdout) : Error(`${stderr->String.trim} ${stdout->String.trim}`->String.trim)
}

/** The driver started again, waited on, for a signal's handler that cannot wait on a promise. */
let startedNow = (target: Remote.target) => {
  let done = Host.spawnSync(
    "ssh",
    [...target.options, target.host, Stopping.start],
    {stdio: ["ignore", "pipe", "pipe"], encoding: "utf8"},
  )
  done.status->Nullable.toOption == Some(0)
}

/** hello asked through the entry, on the machine. */
let throughEntry = (target, ~binding) =>
  async () =>
    (await remote(target, Live.hello(~app, ~binding)))
    ->Result.flatMap(Live.readAnswered)
    ->Result.flatMap(Live.greeted)

/** hello asked through the tunnel, from here. */
let throughTunnel = address =>
  async () =>
    switch await Host.fetchWithin(address, 5000) {
    | response => Live.greeted({status: response->Host.status, body: await response->Host.text})
    | exception JsExn(e) => Error(e->JsExn.message->Option.getOr("not reached"))
    }

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

/** The driver's state, its list and hello through each path, asked once. */
let looked = async (target, paths, ~when_) => {
  let state = (await remote(target, Stopping.state))->Result.map(String.trim)
  let list =
    (await remote(target, Live.described))
    ->Result.flatMap(Live.readAnswered)
    ->Result.flatMap(Live.list)
  let hello = []
  for i in 0 to paths->Array.length - 1 {
    switch paths->Array.get(i) {
    | Some((path, ask)) => hello->Array.push((`hello answers through the ${path}`, await ask()))
    | None => ()
    }
  }
  let checks = [
    (
      `${Stopping.unit} is active`,
      switch state {
      | Ok("active") => Ok()
      | Ok(other) => Error(other)
      | Error(why) => Error(why)
      },
    ),
    ("describe answers a list of the contract's shape", list->Result.map(_ => ())),
    ...hello,
  ]
  (list, told(when_, checks))
}

/** A path asked every half second until the window ends, each ask timed. */
let watched = async (ask, ~until) => {
  let asks: array<Tally.asked> = []
  while Date.now() < until {
    let began = Date.now()
    let answer = await ask()
    asks->Array.push({began, ended: Date.now(), answer})
    let left = every -. (Date.now() -. began)
    if left > 0. {
      await Host.sleep(Float.toInt(left))
    }
  }
  asks
}

/** A call of the stopped driver made, and whether it was refused at once. */
let probed = async (target: Remote.target, shell) => {
  let began = Date.now()
  let {code, stdout, stderr}: Run.ran = await Run.run(
    "ssh",
    [...target.options, target.host, Stopping.statused(shell)],
  )
  let took = Date.now() -. began
  code == 0 ? Stopping.refused(stdout, ~took) : Error(`ssh failed, ${stderr->String.trim}`)
}

/** The driver stopped, each path watched through the window, and its calls made while stopped. */
let lost = async (target, paths) =>
  switch await remote(target, Stopping.stop) {
  | Error(why) => Error(`${Stopping.unit} did not stop, ${why}`)
  | Ok(_) =>
    let from = Date.now()
    let until = from +. window
    let names = paths->Array.map(((path, _)) => path)->Array.join(" and ")
    say(`${Stopping.unit} stopped, hello asked through the ${names} for ${seconds(window)}s`)
    let tallies = await Promise.all(
      paths->Array.map(async ((path, ask)) =>
        Tally.tally(~path, ~from, ~until, await watched(ask, ~until))
      ),
    )
    let calls = [
      ("management's describe", Live.described),
      ("deployments' describe", Live.deployment(~app)),
    ]
    let refusals = []
    for i in 0 to calls->Array.length - 1 {
      switch calls->Array.get(i) {
      | Some((what, shell)) => refusals->Array.push((what, await probed(target, shell)))
      | None => ()
      }
    }
    Ok((tallies, refusals))
  }

/** What the window showed, said, and whether every path answered and every call was refused. */
let reported = ((tallies, refusals)) => {
  tallies->Array.forEach(t => say(`during, ${Tally.line(t)}`))
  let refused = refusals->Array.reduce(true, (held, (what, result)) =>
    switch result {
    | Ok(how) =>
      say(`during, ${what} ${how}`)
      held
    | Error(why) =>
      say(`during, failed: ${what}, ${why}`)
      false
    }
  )
  tallies->Array.every(Tally.held) && refused
}

let main = async () => {
  let started = Date.now()
  let took = () => seconds(Date.now() -. started)
  let args = Host.argv->Array.slice(~start=2)
  let dry = args->Array.includes("--dry-run")
  switch args->Array.filter(a => a != "--dry-run") {
  | [named] if !(named->String.startsWith("--")) =>
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
      | Ok("") | Error(_) => []
      | Ok(address) => [("tunnel", throughTunnel(address))]
      }
      let paths = [("entry", throughEntry(target, ~binding)), ...tunnel]
      let (before, held) = await looked(target, paths, ~when_="before")
      if !held {
        say(`${named} does not serve as it should, so nothing is stopped, ${took()}s`)
        Host.setExitCode(Host.process, 1)
      } else if dry {
        say(`nothing stopped, as --dry-run asks, ${took()}s`)
      } else {
        let again = () => {
          let back = startedNow(target)
          say(back ? `${Stopping.unit} started again` : `failed: ${Stopping.unit} did not start`)
          back
        }
        ["SIGINT", "SIGTERM", "SIGHUP"]->Array.forEach(signal =>
          Host.onSignal(Host.process, signal, () => {
            again()->ignore
            Host.exit(Host.process, 130)
          })
        )
        let lost = try await lost(target, paths) catch {
        | JsExn(e) => Error(e->JsExn.message->Option.getOr("the run threw"))
        }
        let back = (await remote(target, Stopping.start))->Result.isOk || again()
        let kept = switch lost {
        | Ok(window) => reported(window)
        | Error(why) =>
          say(`failed: ${why}`)
          false
        }
        let (after, still) = await looked(target, paths, ~when_="after")
        let same = switch (before, after) {
        | (Ok(b), Ok(a)) =>
          Contracts.ManagementDescribed.toJson(b) == Contracts.ManagementDescribed.toJson(a)
        | (Error(_), _) | (_, Error(_)) => false
        }
        say(same ? "after, the live list is as it was" : "failed: the live list changed")
        let met = kept && back && still && same
        say(
          `${named} ${met
              ? "keeps serving while its driver is stopped"
              : "does not keep serving while its driver is stopped"}, ${took()}s`,
        )
        Host.setExitCode(Host.process, met ? 0 : 1)
      }
    }
  | _ =>
    Console.error(`lose: ${usage}`)
    Host.setExitCode(Host.process, 2)
  }
}

await main()
