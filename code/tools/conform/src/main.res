/***
 * The kinds' samples run on a second driver beside the one a test machine runs, the live one asked
 * and hello watched throughout, and all the run made removed, RFC n0o4l; only order is here.
 */
module Contracts = Envelope.Contracts

let usage = "conform <target> [--dry-run]"

/** The kinds whose samples the machine's driver is held to, each a directory of `tests/kinds/`. */
let kinds = ["management", "deployments", "objects", "databases"]

/** The app whose deployment hello is, as deploy makes it. */
let app = 1

/** What a case of each kind is held where it gives none, a container as deploy holds hello's. */
let holding = `{
  "deployments": {"millicores": 500, "memory": 268435456},
  "object": {"size": 268435456},
  "database": {"size": 268435456}
}`

let say = line => Console.log(`conform: ${line}`)

/** A program run, what it wrote, or why it failed with what it wrote to stderr. */
let ran = (program, args, ~input=?) => {
  let done = Host.spawnSync(
    program,
    args,
    {?input, stdio: ["pipe", "pipe", "pipe"], encoding: "utf8"},
  )
  let said = text => text->Nullable.toOption->Option.getOr("")
  switch done.status->Nullable.toOption {
  | Some(0) => Ok(said(done.stdout))
  | _ =>
    Error(
      `${program} failed, ${said(done.stderr)->String.trim} ${said(
          done.stdout,
        )->String.trim}`->String.trim,
    )
  }
}

let remote = (target: Remote.target, command) =>
  ran("ssh", [...target.options, target.host, command])

/** A file of this machine's written to the machine through a shell reading stdin. */
let sent = (target: Remote.target, path, command) => {
  let done = Host.spawnSyncBytes(
    "ssh",
    [...target.options, target.host, command],
    {input: Host.readBytes(path), stdio: ["pipe", "pipe", "pipe"], encoding: "utf8"},
  )
  switch done.status->Nullable.toOption {
  | Some(0) => Ok()
  | _ => Error(`ssh failed, ${done.stderr->Nullable.toOption->Option.getOr("")->String.trim}`)
  }
}

/**
 * The runner's fixtures built into a directory here and copied to the one the machine serves, the
 * padded made there, or why they are not.
 */
let fixtures = (target, facts: Instance.facts, ~scratch, ~local) => {
  let built = `${scratch}/fixtures`
  let bounds = `${scratch}/bounds.json`
  Host.writeText(
    bounds,
    JSON.stringify(
      JSON.Object(facts.largest->Option.mapOr(dict{}, n => dict{"artifact": JSON.Number(n)})),
    ),
  )
  let directory = Instance.served(local)
  ran(
    Host.execPath,
    [
      Host.fromRoot("code/tools/runner/src/build.res.mjs"),
      "--into",
      built,
      "--bounds",
      bounds,
      ...facts.architecture->Option.mapOr([], a => ["--architecture", a]),
    ],
  )
  ->Result.flatMap(said => {
    said->String.split("\n")->Array.filter(l => l != "")->Array.forEach(l => say(`fixtures, ${l}`))
    Instance.readFixtures(Host.readText(`${built}/fixtures.json`))
  })
  ->Result.flatMap(made =>
    remote(target, Instance.emptied(directory))
    ->Result.flatMap(_ =>
      made.files->Array.reduce(
        Ok(),
        (copied, file) =>
          copied->Result.flatMap(
            () => sent(target, `${built}/${file}`, Instance.copied(~directory, ~file)),
          ),
      )
    )
    ->Result.flatMap(() => remote(target, Instance.made(~directory, made.padded)))
    ->Result.map(_ => (built, directory))
  )
}

/** Every behavior file of the kinds by its path from the root, and how many cases each holds. */
let samples = () =>
  kinds->Array.flatMap(kind => {
    let directory = `tests/kinds/${kind}`
    Host.list(Host.fromRoot(directory))
    ->Array.filter(name => name->String.endsWith(".json"))
    ->Array.toSorted(String.compare)
    ->Array.map(name => {
      let path = `${directory}/${name}`
      let cases =
        JSON.parseOrThrow(Host.readText(Host.fromRoot(path)))
        ->JSON.Decode.object
        ->Option.flatMap(o => o->Dict.get("cases"))
        ->Option.flatMap(JSON.Decode.array)
        ->Option.mapOr(0, Array.length)
      (path, cases)
    })
  })

/** The live driver's list, its refusals and hello, each with what it showed or why it failed. */
let asked = async (target, facts: Instance.facts) => {
  let ask = (command, read) =>
    remote(target, command)->Result.flatMap(Live.readAnswered)->Result.flatMap(read)
  let list = ask(Live.described, Live.list)
  let tunnel = switch remote(target, Live.tunnel)->Result.map(String.trim) {
  | Ok("") | Error(_) => None
  | Ok(address) =>
    Some(
      switch await Host.fetchWithin(address, 10000) {
      | response => Live.greeted({status: response->Host.status, body: await response->Host.text})
      | exception JsExn(e) => Error(e->JsExn.message->Option.getOr("not reached"))
      },
    )
  }
  let checks = [
    ("describe answers a list of the contract's shape", list->Result.map(_ => ())),
    ("a call with no token is denied", ask(Live.untokened, Live.denied)),
    ("an unknown interface is refused", ask(Live.unknown, Live.refused)),
    (
      `the entry answers hello for app-${Int.toString(app)}.b${Int.toString(facts.binding)}`,
      ask(Live.hello(~app, ~binding=facts.binding), Live.greeted),
    ),
    ...tunnel->Option.mapOr([], answered => [("the tunnel answers hello", answered)]),
  ]
  (list, checks)
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

/** hello asked every two seconds until `running` says the run is over, its answers counted. */
let watched = async (target, facts: Instance.facts, running) => {
  let asked = ref(0)
  let answered = ref(0)
  while running() {
    asked := asked.contents + 1
    let said =
      remote(target, Live.hello(~app, ~binding=facts.binding))
      ->Result.flatMap(Live.readAnswered)
      ->Result.flatMap(Live.greeted)
    switch said {
    | Ok() => answered := answered.contents + 1
    | Error(why) => say(`during, hello did not answer, ${why}`)
    }
    await Host.sleep(2000)
  }
  (answered.contents, asked.contents)
}

/** The forward answering, asked for ten seconds. */
let rec reached = async (base, ~left=100) =>
  switch await Host.fetchWithin(base, 1000) {
  | _ => true
  | exception JsExn(_) if left > 0 =>
    await Host.sleep(100)
    await reached(base, ~left=left - 1)
  | exception JsExn(_) => false
  }

/** What runs beside the tool, the forward and the runner, stopped with it when it is stopped. */
let children = []

/** The samples run by the runner on the instance through a forward, hello watched beside them. */
let run = async (target: Remote.target, facts, tokens, files, ~scratch, ~served) => {
  let local = await Host.freePort()
  let forward = Host.spawn(
    "ssh",
    Remote.forward(target, ~local, ~remote=Instance.port),
    {stdio: ["ignore", "ignore", "inherit"]},
  )
  children->Array.push(forward)
  let base = `http://localhost:${Int.toString(local)}`
  let code = if await reached(base) {
    let runner = Host.spawn(
      Host.execPath,
      [
        Host.fromRoot("code/tools/runner/src/main.res.mjs"),
        "--base",
        base,
        "--tokens",
        "-",
        "--waits",
        Host.fromRoot("code/tools/conform/waiting.json"),
        "--bounds",
        `${scratch}/bounds.json`,
        "--held",
        `${scratch}/held.json`,
        // A send is made on the machine, as only it reaches a deployment's address on its bridge.
        "--send-through",
        JSON.stringify(
          JSON.Array([...target.options, target.host]->Array.map(a => JSON.String(a))),
        ),
        ...served->Option.mapOr([], ((built, directory)) => [
          "--fixtures",
          built,
          "--served",
          `file://${directory}`,
        ]),
        ...files,
      ],
      {stdio: ["pipe", "inherit", "inherit"], cwd: Host.fromRoot(".")},
    )
    children->Array.push(runner)
    runner->Host.stdin->Host.endWith(tokens->Array.join("\n") ++ "\n")
    let over = ref(false)
    let watching = watched(target, facts, () => !over.contents)
    let code = await Host.ended(runner)
    over := true
    let (answered, asked) = await watching
    say(`during, hello answered ${Int.toString(answered)} of ${Int.toString(asked)} times`)
    answered == asked ? code : Math.Int.max(code, 1)
  } else {
    say("failed: the forward to the instance never answered")
    1
  }
  forward->Host.kill->ignore
  code
}

/** Everything the instance made removed, each said, and whether nothing is left. */
let clean = (target, facts: Instance.facts, ~when_) =>
  switch remote(
    target,
    Instance.cleaned(
      ~mount=facts.mount,
      ~subvolumes=facts.subvolumes,
      ~served=facts.local->Option.map(Instance.served),
    ),
  ) {
  | Error(why) =>
    say(`${when_}, failed to clean, ${why}`)
    false
  | Ok(text) =>
    let {removed, left}: Instance.cleaned = Instance.readCleaned(text)
    removed->Array.forEach(what => say(`${when_}, removed ${what}`))
    left->Array.forEach(what => say(`${when_}, failed: left ${what}`))
    left == []
  }

let main = async () => {
  let started = Date.now()
  let took = () => ((Date.now() -. started) /. 1000.)->Float.toFixed(~digits=1)
  let args = Host.argv->Array.slice(~start=2)
  let dry = args->Array.includes("--dry-run")
  switch args->Array.filter(a => a != "--dry-run") {
  | [named] if !(named->String.startsWith("--")) =>
    let target = Remote.target(named)
    let files = samples()
    let count = files->Array.reduce(0, (n, (_, cases)) => n + cases * 2)
    switch remote(target, Instance.facts)->Result.flatMap(Instance.readFacts) {
    | Error(why) =>
      say(`failed: ${named} cannot hold a second driver, ${why}`)
      Host.setExitCode(Host.process, 1)
    | Ok(facts) =>
      switch Instance.subnet(facts.routes) {
      | None =>
        say(`failed: every subnet of its own overlaps a route of ${named}`)
        Host.setExitCode(Host.process, 1)
      | Some(subnet) =>
        let (before, checks) = await asked(target, facts)
        let held = told("before", checks)
        say(
          `${Int.toString(files->Array.length)} behavior files, ${Int.toString(
              count,
            )} bindings from ${Int.toString(
              Instance.first,
            )}, one for each case in each form, on ${Instance.unit}, its bridge ${Instance.bridge}`,
        )
        if dry {
          say(`nothing started, as --dry-run asks, ${took()}s`)
          Host.setExitCode(Host.process, held ? 0 : 1)
        } else {
          let cleaned = clean(target, facts, ~when_="from an earlier run")
          let scratch = Host.mkdtemp(`${Host.tmpdir()}/monoflake-conform-`)
          let forget = () => Host.rm(scratch, {recursive: true, force: true})
          Host.writeText(`${scratch}/held.json`, holding)
          let served = switch facts.local {
          | None =>
            say("the live driver names no --local directory, so no fixture is served")
            None
          | Some(local) =>
            switch fixtures(target, facts, ~scratch, ~local) {
            | Ok((built, directory)) =>
              say(`fixtures copied to ${directory}, ${took()}s`)
              Some((built, directory))
            | Error(why) =>
              say(`no fixture is served, ${why}`)
              None
            }
          }
          let code = switch remote(
            target,
            Instance.started(~count, ~subnet),
          )->Result.flatMap(text => Instance.readTokens(text, ~count)) {
          | Error(why) =>
            say(`failed: the second driver did not start, ${why}`)
            1
          | Ok(tokens) =>
            say(`started ${Instance.unit} from the binary the live driver runs, ${took()}s`)
            Host.onSignal(Host.process, "SIGINT", () => {
              children->Array.forEach(child => child->Host.kill->ignore)
              clean(target, facts, ~when_="stopped")->ignore
              forget()
              Host.exit(Host.process, 130)
            })
            await run(
              target,
              facts,
              tokens,
              files->Array.map(((path, _)) => path),
              ~scratch,
              ~served,
            )
          }
          forget()
          let nothingLeft = clean(target, facts, ~when_="after")
          if nothingLeft {
            say("after, nothing the run made is left")
          }
          let (after, checks) = await asked(target, facts)
          let still = told("after", checks)
          let same = switch (before, after) {
          | (Ok(b), Ok(a)) =>
            Contracts.ManagementDescribed.toJson(b) == Contracts.ManagementDescribed.toJson(a)
          | (Error(_), _) | (_, Error(_)) => false
          }
          say(same ? "after, the live list is as it was" : "failed: the live list changed")
          let met = code == 0 && held && still && same && nothingLeft && cleaned
          say(
            `${named} ${met
                ? "meets its contracts, but what waits"
                : "does not meet its contracts"}, ${took()}s`,
          )
          Host.setExitCode(Host.process, met ? 0 : 1)
        }
      }
    }
  | _ =>
    Console.error(`conform: ${usage}`)
    Host.setExitCode(Host.process, 2)
  }
}

await main()
