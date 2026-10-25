/***
 * An app's Worker built, packed, copied to a test machine, deployed through its driver and asked
 * through the entry, each phase timed, RFC n0o4l; only order is decided here.
 */
module Contracts = Envelope.Contracts

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

/**
 * The app's id, the one given, or one drawn where none is that neither the machine's list nor its
 * deployments hold, as no control is there to draw it.
 */
let appOf = (target, app) =>
  switch app {
  | Some(app) => Ok((app, "given"))
  | None =>
    describeList(target)
    ->Result.mapError(refusal)
    ->Result.flatMap(described => {
      let listed = Drawing.listed(described)
      Drawing.drawn(
        ~random=() => Ids.Id.ofBytes(Host.fillRandom(Uint8Array.fromLength(4))),
        ~held=id =>
          listed->Array.includes(id)
            ? Ok(true)
            : switch describeDeployment(target, id) {
              | Error({reason: "not_found"}) => Ok(false)
              | Ok(_) => Ok(true)
              | Error(refused) => Error(refusal(refused))
              },
      )->Result.map(id => (id, "drawn, as no control draws it"))
    })
  }

/** The archive sent to the machine and deployed there, then the entry asked for the app. */
let sent = async (named, ~app, ~hash, ~path, ~facts: Machine.facts, ~binding, ~dry) => {
  let target = Machine.target(named)
  let address = Deploying.address(~directory=facts.directory, ~hash)
  let copy = dry
    ? async () => Ok("nothing copied, as --dry-run asks")
    : async () => copied(target, path, facts, Deploying.fileName(hash))
  let answered = await timed(
    "app",
    async () => appOf(target, app),
    ((app, how)) => `${Ids.Id.text(app)}, ${how}`,
  )
  ->after(((app, _)) =>
    timed("copy", copy, said => said)->Promise.thenResolve(r => r->Result.map(_ => app))
  )
  ->after(app =>
    timed("list", () => listed(target, ~dry), ((_, said)) => said)->Promise.thenResolve(r =>
      r->Result.map(((into, _)) => (app, into))
    )
  )
  ->after(((app, into)) =>
    timed(
      "deploy",
      () => deployed(target, ~app, ~hash, ~address, ~into, ~dry),
      said => said,
    )->Promise.thenResolve(r => r->Result.map(_ => app))
  )
  ->after(async app => {
    let host = Deploying.host(~app, ~binding)
    dry
      ? Ok((app, host, None))
      : (
          await timed(
            "answer",
            async () => remote(target, Machine.asked(host)),
            _ => `the entry for ${host} answered`,
          )
        )->Result.map(answer => (app, host, Some(answer)))
  })
  answered->Result.map(((app, host, answer)) => {
    Console.log(`deploy: app ${Ids.Id.text(app)}`)
    answer->Option.forEach(answer => {
      Console.log(answer)
      if Machine.isLocal(named) {
        Console.log(`deploy: open curl -H 'Host: ${host}.local' http://localhost:8080/`)
      }
      facts.tunnel->Option.forEach(
        tunnel => Console.log(`deploy: open ${tunnel}, the machine's tunnel`),
      )
    })
  })
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

/** The id a control answered a deploy with, the app it drew where none was given. */
let ranAs = (described: Contracts.DeploymentDescribed.t) =>
  switch described.runs {
  | App({id}) => Ok(id)
  | Component({component}) => Error(`the control answered the component ${component}, no app`)
  }

/**
 * The release put, deployed onto the binding and running through a control, then asked there, a
 * new app opened where none is given and its id the control drew said.
 */
let throughControl = async (
  control: Control.t,
  ~app,
  ~binding,
  ~hash,
  ~path,
  ~secrets,
  ~network,
  ~dry,
) => {
  let progress = async app =>
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
      switch await Control.deploy(control, ~binding, ~app, ~hash, ~secrets, ~network) {
      | Error(refused) =>
        Error(Drawing.retried(~given=app, ~drawn=Drawing.named(refused.message), refusal(refused)))
      | Ok(described) =>
        switch ranAs(described) {
        | Error(why) => Error(why)
        | Ok(id) =>
          (await polled(() => progress(id), running))
          ->Result.map(() => id)
          ->Result.mapError(why => Drawing.retried(~given=app, ~drawn=Some(id), why))
        }
      }
    }
  let described = switch app {
  // A new app has nothing to describe until the control draws its id.
  | None => Promise.resolve(Ok(Deploying.Elsewhere))
  | Some(app) =>
    timed(
      "describe",
      () => progress(app),
      p =>
        switch p {
        | Deploying.Running => "running this version already"
        | Waiting | Elsewhere | Failed(_) => "not running this version"
        },
    )
  }
  let answered = await described
  ->after(async p =>
    switch (p, app) {
    | (Deploying.Running, Some(app)) =>
      Console.log("deploy: running this version already, nothing sent")
      Ok(Some(app))
    | (Running | Waiting | Elsewhere | Failed(_), _) if dry =>
      let as_ = app->Option.mapOr("a new app the control draws", app => `app ${Ids.Id.text(app)}`)
      Console.log(
        `deploy: the release would be put and deployed onto binding ${Ids.Id.text(
            binding,
          )} as ${as_}`,
      )
      Ok(app)
    | (Running | Waiting | Elsewhere | Failed(_), _) =>
      (
        await timed("deploy", sent, id =>
          `binding ${Ids.Id.text(binding)}, app ${Ids.Id.text(id)}, deployed and running`
        )
      )->Result.map(id => Some(id))
    }
  )
  ->after(async app =>
    switch app {
    | Some(app) if !dry =>
      (
        await timed("answer", () => Control.asked(control, ~app), _ => "the gateway answered")
      )->Result.map(answer => Some((app, answer)))
    | Some(_) | None => Ok(None)
    }
  )
  answered->Result.map(answer =>
    answer->Option.forEach(((app, answer)) => {
      Console.log(answer)
      Console.log(`deploy: app ${Ids.Id.text(app)}`)
      Console.log(`deploy: open ${Control.gateway(~origin=control.origin, ~app)}`)
    })
  )
}

/** Each secret named, its value the environment's variable of its name, or the first unset. */
let secretsOf = names =>
  names->Array.reduce(Ok(dict{}), (held, name) =>
    held->Result.flatMap(held =>
      switch Host.env->Dict.get(name) {
      | Some(value) if value != "" =>
        held->Dict.set(name, Bytes.utf8(value))
        Ok(held)
      | Some(_) | None => Error(`the secret ${name} is unset in the environment`)
      }
    )
  )

/** The control a target names, with the operator's secret, or why it cannot be called. */
let controlOf = named =>
  Control.origin(named)->Option.map(origin =>
    switch (origin, Host.env->Dict.get(Control.operatorVariable)) {
    | (Error(why), _) => Error(why)
    | (Ok(_), None | Some("")) =>
      Error(`${Control.operatorVariable} holds no operator's secret for the control`)
    | (Ok(origin), Some(operator)) => Ok(({origin, operator, fetch: Web.fetch}: Control.t))
    }
  )

/** The control a deploy is sent through, with the binding it deploys onto. */
let deployingOf = (named, binding) =>
  controlOf(named)->Option.map(control =>
    control->Result.flatMap(control =>
      switch binding {
      | Some(binding) => Ok((control, binding))
      | None => Error(`a control's target asks --binding, the binding to deploy onto`)
      }
    )
  )

/** The binding's id its token names before its dot, a decimal, as a token writes it. */
let tokenBinding = (facts: Machine.facts) =>
  switch Float.fromString(facts.binding) {
  | Some(id) if /^[1-9][0-9]{0,9}$/->RegExp.test(facts.binding) && id <= 4294967295. =>
    Ok((facts, id))
  | Some(_) | None => Error(`the binding's token names ${facts.binding}, no binding's id`)
  }

/** The app a control drew and never ran, forgotten there, or what a dry run would ask. */
let forgotten = async (control: Control.t, ~app, ~dry) =>
  if dry {
    Ok(`app ${Ids.Id.text(app)} would be forgotten`)
  } else {
    switch await Control.forget(control, ~app) {
    | Ok({app}) => Ok(`app ${Ids.Id.text(app)} forgotten`)
    | Error(refused) => Error(refusal(refused))
    }
  }

/** The app that ran retired through a control, or what a dry run would ask. */
let retired = async (control: Control.t, ~app, ~dry) =>
  if dry {
    Ok(`app ${Ids.Id.text(app)} would be stopped, deleted by its driver and removed`)
  } else {
    switch await Control.retire(control, ~app) {
    | Ok({app}) => Ok(`app ${Ids.Id.text(app)} retired`)
    | Error(refused) => Error(refusal(refused))
    }
  }

/** A call a control's target alone takes, timed under its name. */
let onControl = async (named, name, run) =>
  // Arguments refused a machine's target already, so this one names a control.
  switch controlOf(named)->Option.getOr(Error(`${named} names no control`)) {
  | Ok(control) =>
    switch await timed(name, () => run(control), said => said) {
    | Ok(_) => ()
    | Error(_) => Host.setExitCode(Host.process, 1)
    }
  | Error(why) =>
    Console.error(`deploy: ${why}`)
    Host.setExitCode(Host.process, 2)
  }

let main = async () => {
  let started = Date.now()
  switch Arguments.parse(Host.argv->Array.slice(~start=2)) {
  | Error(why) =>
    Console.error(`deploy: ${why}`)
    Host.setExitCode(Host.process, 2)
  | Ok({target: named, forget: Some(app), dry}) =>
    await onControl(named, "forget", control => forgotten(control, ~app, ~dry))
  | Ok({target: named, retire: Some(app), dry}) =>
    await onControl(named, "retire", control => retired(control, ~app, ~dry))
  | Ok({target: named, secrets, network})
    if Control.origin(named) == None && (secrets != [] || network != []) =>
    Console.error(`deploy: --secrets and --network are a control's, and ${named} is a machine`)
    Host.setExitCode(Host.process, 2)
  | Ok({secrets}) if secretsOf(secrets)->Result.isError =>
    secretsOf(secrets)->Result.mapError(why => Console.error(`deploy: ${why}`))->ignore
    Host.setExitCode(Host.process, 2)
  | Ok({target: named, binding})
    if deployingOf(named, binding)->Option.mapOr(false, Result.isError) =>
    deployingOf(named, binding)->Option.forEach(c =>
      c->Result.mapError(why => Console.error(`deploy: ${why}`))->ignore
    )
    Host.setExitCode(Host.process, 2)
  | Ok({directory, target: named, app, binding, secrets, network, dry}) =>
    let secrets = secretsOf(secrets)->Result.getOr(dict{})
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
      switch deployingOf(named, binding) {
      | Some(Ok((control, binding))) =>
        throughControl(control, ~app, ~binding, ~hash, ~path, ~secrets, ~network, ~dry)
      | Some(Error(why)) => Promise.resolve(Error(why))
      | None =>
        timed(
          "ask",
          async () =>
            remote(Machine.target(named), Machine.facts)
            ->Result.flatMap(Machine.readFacts)
            ->Result.flatMap(tokenBinding),
          ((_, binding)) => `binding ${Ids.Id.text(binding)}`,
        )->after(((facts, binding)) => sent(named, ~app, ~hash, ~path, ~facts, ~binding, ~dry))
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
