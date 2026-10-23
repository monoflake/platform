/***
 * An app's Worker built, packed, copied to a test machine, deployed through its driver and asked
 * through the entry, each phase timed, RFC n0o4l; only order is decided here.
 */
module Contracts = Envelope.Contracts

let usage = "deploy <app directory> <target> [--app <id>] [--binding <id>] [--dry-run]"

/**
 * The arguments, the app's directory, the target, the app's id, the binding a control deploys it
 * onto, and whether nothing is changed.
 */
type args = {directory: string, target: string, app: float, binding: option<float>, dry: bool}

let id = text =>
  switch Float.fromString(text) {
  | Some(n) if Math.floor(n) == n && n >= 1. => Some(n)
  | _ => None
  }

let rec parse = (args, given) =>
  switch args {
  | list{"--dry-run", ...rest} => parse(rest, {...given, dry: true})
  | list{"--app", text, ...rest} =>
    switch id(text) {
    | Some(app) => parse(rest, {...given, app})
    | None => Error(`--app ${text} is no id`)
    }
  | list{"--binding", text, ...rest} =>
    switch id(text) {
    | Some(binding) => parse(rest, {...given, binding: Some(binding)})
    | None => Error(`--binding ${text} is no id`)
    }
  | list{flag, ..._} if flag->String.startsWith("--") => Error(`${flag} is no flag of ${usage}`)
  | list{named, ...rest} if given.directory == "" => parse(rest, {...given, directory: named})
  | list{named, ...rest} if given.target == "" => parse(rest, {...given, target: named})
  | list{named, ..._} => Error(`${named} is one argument too many`)
  | list{} if given.target == "" => Error(usage)
  | list{} => Ok(given)
  }

/** A phase run and its time printed, beside what `said` makes of its value or why it failed. */
let timed = async (name, run, said) => {
  let started = Date.now()
  let result = await run()
  let took = ((Date.now() -. started) /. 1000.)->Float.toFixed(~digits=2)
  switch result {
  | Ok(value) => Console.log(`deploy: ${name} ${took}s, ${said(value)}`)
  | Error(why) => Console.error(`deploy: ${name} failed after ${took}s, ${why}`)
  }
  result
}

/** A program run, what it wrote, or why it failed with what it wrote to stderr. */
let ran = (program, args, ~cwd=?, ~input=?, ~env=?) => {
  let done = Host.spawnSync(
    program,
    args,
    {?cwd, ?input, ?env, stdio: ["pipe", "pipe", "pipe"], encoding: "utf8"},
  )
  let said = text => text->Nullable.toOption->Option.getOr("")->String.trim
  switch done.status->Nullable.toOption {
  | Some(0) => Ok(said(done.stdout))
  | _ => Error(`${program} failed, ${said(done.stderr)} ${said(done.stdout)}`->String.trim)
  }
}

let remote = (target: Machine.target, command, ~input=?) =>
  ran("ssh", [...target.options, target.host, command], ~input?)

/** A call of an operation on the machine, its output read as its type. */
let called = (target, envelope, data) =>
  remote(target, Machine.call(envelope), ~input=JSON.stringify(envelope))
  ->Result.mapError((why): Machine.refused => {reason: "unreached", message: why})
  ->Result.flatMap(text => Machine.answer(text, data))

/** A call's envelope as JSON, with no capability since the binding's token stands for one. */
let management = call => Contracts.Interface.Management.toJson({call, capabilities: []})
let deployments = call => Contracts.Interface.Deployments.toJson({call, capabilities: []})

let refusal = ({reason, message}: Machine.refused) => `${reason}: ${message}`

let describeList = target =>
  called(target, management(Describe({})), Contracts.ManagementDescribed.fromJson)

let describeDeployment = (target, app) =>
  called(target, deployments(Describe(Deploying.of_(app))), Contracts.DeploymentDescribed.fromJson)

/** The wrangler configuration wrangler itself would read first, its JSON forms alone. */
let configOf = directory =>
  switch ["wrangler.json", "wrangler.jsonc"]
  ->Array.map(name => Host.join([directory, name]))
  ->Array.find(Host.exists) {
  | Some(path) => Bundle.config(Host.readText(path))->Result.mapError(why => `${path}: ${why}`)
  | None => Error(`${directory} holds no wrangler.json or wrangler.jsonc`)
  }

/** wrangler's own bundle of the app, built into a directory of its own. */
let built = (directory, into) => {
  let wrangler = Host.join([directory, "node_modules", ".bin", "wrangler"])
  if !Host.exists(wrangler) {
    Error(`${wrangler} is not installed, so the app's own install comes first`)
  } else {
    let env = Dict.copy(Host.env)
    env->Dict.set("WRANGLER_SEND_METRICS", "false")
    ran(wrangler, ["deploy", "--dry-run", "--outdir", into], ~cwd=directory, ~env)
    ->Result.flatMap(_ => configOf(directory))
    ->Result.map(config => (config, into))
  }
}

/** What wrangler wrote packed as a bundle, its hash, and the archive written beside it. */
let packed = ((config, outdir), scratch) => {
  let files =
    Host.list(outdir, {recursive: true})
    ->Array.filter(name => Host.stat(Host.join([outdir, name]))->Host.isFile)
    ->Array.map((name): Bundle.file => {name, bytes: Host.readBytes(Host.join([outdir, name]))})
  Bundle.packed(config, files)->Result.map(archive => {
    let hash = Host.sha256(archive)
    let path = Host.join([scratch, Deploying.fileName(hash)])
    Host.writeBytes(path, archive)
    (hash, path, archive->TypedArray.length)
  })
}

/** The archive copied in by its hash, a file already there of that name being the same. */
let copied = (target: Machine.target, path, facts: Machine.facts, name) => {
  let into = `${facts.directory}/${name}`
  switch remote(target, `test -f ${into} && echo held || true`) {
  | Ok("held") => Ok("already there")
  | Ok(_) =>
    ran(
      "rsync",
      ["-z", "-e", ["ssh", ...target.options]->Array.join(" "), path, `${target.host}:${into}`],
    )->Result.map(_ => `to ${into}`)
  | Error(why) => Error(why)
  }
}

/** Asked again until `ready` says it is done or a minute has passed. */
let rec waited = async (ask, ready, ~left=300) =>
  switch ask()->Result.flatMap(ready) {
  | Ok(Some(value)) => Ok(value)
  | Ok(None) if left > 0 =>
    await Host.sleep(200)
    await waited(ask, ready, ~left=left - 1)
  | Ok(None) => Error("not ready after a minute")
  | Error(why) => Error(why)
  }

/** A phase's value handed to the next phase, or the first failure. */
let after = async (phase, next) =>
  switch await phase {
  | Ok(value) => await next(value)
  | Error(why) => Error(why)
  }

/** The list sent with a container for the app if it holds none, and that container made. */
let listed = async (target, ~dry) =>
  switch describeList(target) {
  | Error(refused) => Error(refusal(refused))
  | Ok(described) =>
    let credential = Host.fillRandom(Uint8Array.fromLength(32))
    switch Listing.planned(described, ~credential) {
    | Error(why) => Error(why)
    | Ok(Held({into})) => Ok((into, `container ${Float.toString(into)} held already`))
    | Ok(Apply({list, into})) =>
      let named = `container ${Float.toString(into)} at generation ${Float.toString(
          list.generation,
        )}`
      if dry {
        Ok((into, `${named} would be sent`))
      } else {
        switch called(target, management(Apply(list)), Contracts.ManagementHeld.fromJson) {
        | Error(refused) => Error(refusal(refused))
        | Ok(_) =>
          (
            await waited(
              () => describeList(target)->Result.mapError(refusal),
              described =>
                switch Listing.madeOf(described, into) {
                | Making => Ok(None)
                | Made => Ok(Some())
                | Failed(why) => Error(why)
                },
            )
          )->Result.map(() => (into, `${named} made`))
        }
      }
    }
  }

/** The app deployed at the bundle's version, unless it already runs it, and running. */
let deployed = async (target, ~app, ~hash, ~address, ~into, ~dry) => {
  let progress = () =>
    switch describeDeployment(target, app) {
    | Ok(described) => Ok(Deploying.progress(described, hash))
    | Error({reason: "not_found"}) => Ok(Deploying.Elsewhere)
    | Error(refused) => Error(refusal(refused))
    }
  let running = progress =>
    switch progress {
    | Deploying.Running => Ok(Some())
    | Waiting | Elsewhere => Ok(None)
    | Failed(why) => Error(why)
    }
  switch progress() {
  | Error(why) => Error(why)
  | Ok(Running) => Ok("running this version already, nothing sent")
  | Ok(Waiting | Elsewhere | Failed(_)) if dry => Ok(`${address} would be deployed`)
  | Ok(Waiting | Elsewhere | Failed(_)) =>
    switch called(
      target,
      deployments(Deploy(Deploying.deploy(~app, ~hash, ~address, ~into))),
      Contracts.DeploymentDescribed.fromJson,
    ) {
    | Error(refused) => Error(refusal(refused))
    | Ok(_) => (await waited(progress, running))->Result.map(() => "deployed and running")
    }
  }
}

/** The archive sent to the machine and deployed there, then the entry asked for the app. */
let sent = async (named, ~app, ~hash, ~path, ~facts: Machine.facts, ~dry) => {
  let target = Machine.target(named)
  let address = Deploying.address(~directory=facts.directory, ~hash)
  let host = Deploying.host(~app, ~binding=facts.binding)
  let copy = dry
    ? async () => Ok("nothing copied, as --dry-run asks")
    : async () => copied(target, path, facts, Deploying.fileName(hash))
  let answered = await timed("copy", copy, said => said)
  ->after(_ => timed("list", () => listed(target, ~dry), ((_, said)) => said))
  ->after(((into, _)) =>
    timed("deploy", () => deployed(target, ~app, ~hash, ~address, ~into, ~dry), said => said)
  )
  ->after(async _ =>
    dry
      ? Ok(None)
      : (
          await timed(
            "answer",
            async () => remote(target, Machine.asked(host)),
            _ => `the entry for ${host} answered`,
          )
        )->Result.map(answer => Some(answer))
  )
  answered->Result.map(answer =>
    answer->Option.forEach(answer => {
      Console.log(answer)
      if Machine.isLocal(named) {
        Console.log(`deploy: open curl -H 'Host: ${host}.local' http://localhost:8080/`)
      }
      facts.tunnel->Option.forEach(
        tunnel => Console.log(`deploy: open ${tunnel}, the machine's tunnel`),
      )
    })
  )
}

/** Asked again until `ready` says it is done or a minute has passed, each ask awaited. */
let rec polled = async (ask, ready, ~left=300) =>
  switch (await ask())->Result.flatMap(ready) {
  | Ok(Some(value)) => Ok(value)
  | Ok(None) if left > 0 =>
    await Host.sleep(200)
    await polled(ask, ready, ~left=left - 1)
  | Ok(None) => Error("not ready after a minute")
  | Error(why) => Error(why)
  }

/** The release put, deployed onto the binding and running through a control, then asked there. */
let throughControl = async (control: Control.t, ~app, ~binding, ~hash, ~path, ~dry) => {
  let progress = async () =>
    switch await Control.describe(control, ~app) {
    | Ok(described) => Ok(Deploying.progress(described, hash))
    | Error({reason: "not_found"}) => Ok(Deploying.Elsewhere)
    | Error(refused) => Error(refusal(refused))
    }
  let running = progress =>
    switch progress {
    | Deploying.Running => Ok(Some())
    | Waiting | Elsewhere => Ok(None)
    | Failed(why) => Error(why)
    }
  let sent = async () =>
    switch await Control.put(control, Host.readBytes(path)) {
    | Error(refused) => Error(refusal(refused))
    | Ok(held) if Envelope.Hex.encode(held.hash) != Envelope.Hex.encode(hash) =>
      Error(`the control kept ${Envelope.Hex.encode(held.hash)}, not the bundle packed`)
    | Ok(_) =>
      switch await Control.deploy(control, ~binding, ~app, ~hash) {
      | Error(refused) => Error(refusal(refused))
      | Ok(_) => (await polled(progress, running))->Result.map(() => "deployed and running")
      }
    }
  let answered = await timed("describe", progress, p =>
    switch p {
    | Deploying.Running => "running this version already"
    | Waiting | Elsewhere | Failed(_) => "not running this version"
    }
  )
  ->after(async p =>
    switch p {
    | Deploying.Running =>
      Console.log("deploy: running this version already, nothing sent")
      Ok("nothing sent")
    | Waiting | Elsewhere | Failed(_) if dry =>
      Console.log(
        `deploy: the release would be put and deployed onto binding ${Float.toString(binding)}`,
      )
      Ok("nothing sent, as --dry-run asks")
    | Waiting | Elsewhere | Failed(_) =>
      await timed("deploy", sent, said => `binding ${Float.toString(binding)}, ${said}`)
    }
  )
  ->after(async _ =>
    dry
      ? Ok(None)
      : (
          await timed("answer", () => Control.asked(control, ~app), _ => "the gateway answered")
        )->Result.map(answer => Some(answer))
  )
  answered->Result.map(answer =>
    answer->Option.forEach(answer => {
      Console.log(answer)
      Console.log(`deploy: open ${Control.gateway(~origin=control.origin, ~app)}`)
    })
  )
}

/** The control a target names, with the operator's secret, or why it cannot be called. */
let controlOf = (named, binding) =>
  Control.origin(named)->Option.map(origin =>
    switch (origin, binding, Host.env->Dict.get(Control.operatorVariable)) {
    | (Error(why), _, _) => Error(why)
    | (Ok(_), None, _) => Error(`a control's target asks --binding, the binding to deploy onto`)
    | (Ok(_), Some(_), None | Some("")) =>
      Error(`${Control.operatorVariable} holds no operator's secret for the control`)
    | (Ok(origin), Some(binding), Some(operator)) =>
      Ok(({origin, operator, fetch: Web.fetch}: Control.t), binding)
    }
  )

let main = async () => {
  let started = Date.now()
  switch parse(
    List.fromArray(Host.argv->Array.slice(~start=2)),
    {directory: "", target: "", app: 1., binding: None, dry: false},
  ) {
  | Error(why) =>
    Console.error(`deploy: ${why}`)
    Host.setExitCode(Host.process, 2)
  | Ok({target: named, binding})
    if controlOf(named, binding)->Option.mapOr(false, Result.isError) =>
    controlOf(named, binding)->Option.forEach(c =>
      c->Result.mapError(why => Console.error(`deploy: ${why}`))->ignore
    )
    Host.setExitCode(Host.process, 2)
  | Ok({directory, target: named, app, binding, dry}) =>
    let directory = Host.absolute(directory)
    let scratch = Host.makeTemporary(Host.join([Host.temporary(), "deploy-"]))
    let result = await timed(
      "build",
      async () => built(directory, Host.join([scratch, "out"])),
      _ => "wrangler's bundle",
    )
    ->after(built =>
      timed(
        "pack",
        async () => packed(built, scratch),
        ((hash, _, size)) => `${Int.toString(size)} bytes, version ${Envelope.Hex.encode(hash)}`,
      )
    )
    ->after(((hash, path, _)) =>
      switch controlOf(named, binding) {
      | Some(Ok((control, binding))) => throughControl(control, ~app, ~binding, ~hash, ~path, ~dry)
      | Some(Error(why)) => Promise.resolve(Error(why))
      | None =>
        timed(
          "ask",
          async () =>
            remote(Machine.target(named), Machine.facts)->Result.flatMap(Machine.readFacts),
          (facts: Machine.facts) => `binding ${facts.binding}`,
        )->after(facts => sent(named, ~app, ~hash, ~path, ~facts, ~dry))
      }
    )
    Host.remove(scratch, {recursive: true, force: true})
    let took = ((Date.now() -. started) /. 1000.)->Float.toFixed(~digits=2)
    switch result {
    | Ok() => Console.log(`deploy: ${directory} on ${named}, ${took}s in all`)
    | Error(_) => Host.setExitCode(Host.process, 1)
    }
  }
}

await main()
