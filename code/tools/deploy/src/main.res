/***
 * An app's Worker built, packed, copied to a test machine, deployed through its driver and asked
 * through the entry, each phase timed, RFC n0o4l; only order is decided here.
 */
module Contracts = Envelope.Contracts

/** Builder in monoflake/machine owns the duration format used here. */
let timed = async (name, run, said) => {
  let started = Date.now()
  let result = await run()
  let took = ((Date.now() -. started) /. 1000.)->Float.toFixed(~digits=1)
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

/** Which deployment an id names, an app's or, with a salt handed, the storage component's. */
let deploymentOf = (~salt: option<dict<Uint8Array.t>>, id) =>
  salt->Option.isSome ? Component.of_(id) : Deploying.of_(id)

let describeDeployment = (target, ~salt, app) =>
  called(
    target,
    deployments(Describe(deploymentOf(~salt, app))),
    Contracts.DeploymentDescribed.fromJson,
  )

/** The wrangler configuration wrangler itself would read first, its JSON forms alone. */
let configOf = directory =>
  switch ["wrangler.json", "wrangler.jsonc"]
  ->Array.map(name => Host.join([directory, name]))
  ->Array.find(Host.exists) {
  | Some(path) => Bundle.config(Host.readText(path))->Result.mapError(why => `${path}: ${why}`)
  | None => Error(`${directory} holds no wrangler.json or wrangler.jsonc`)
  }

/** The release declarations read before the app is built. */
let releaseOf = (directory, ~ingress) => {
  let path = Host.join([directory, "metadata.json"])
  Host.exists(path)
    ? Bundle.release(~ingress?, Host.readText(path))->Result.mapError(why => `${path} ${why}`)
    : Ok(({kinds: None, ingress, slots: None, functions: None}: Bundle.release))
}

/** The app built into a temporary directory after its release declarations are read. */
let built = (directory, into, ~ingress, ~environment=?) => {
  let wrangler = Host.join([directory, "node_modules", ".bin", "wrangler"])
  releaseOf(directory, ~ingress)->Result.flatMap(release =>
    if !Host.exists(wrangler) {
      Error(`${wrangler} is not installed, so the app's own install comes first`)
    } else {
      let env = switch environment {
      | Some(env) => env
      | None => Dict.copy(Host.env)
      }
      env->Dict.set("WRANGLER_SEND_METRICS", "false")
      ran(wrangler, ["deploy", "--dry-run", "--outdir", into], ~cwd=directory, ~env)
      ->Result.flatMap(_ => configOf(directory))
      ->Result.map(config => (config, release, into))
    }
  )
}

/** The bundle and its release declarations, identified together by the archive hash. */
let packed = ((config, release: Bundle.release, outdir), scratch) => {
  let files =
    Host.list(outdir, {recursive: true})
    ->Array.filter(name => Host.stat(Host.join([outdir, name]))->Host.isFile)
    ->Array.map((name): Bundle.file => {name, bytes: Host.readBytes(Host.join([outdir, name]))})
  Bundle.packed(
    ~kinds=?release.kinds,
    ~ingress=?release.ingress,
    ~slots=?release.slots,
    ~functions=?release.functions,
    config,
    files,
  )->Result.map(archive => {
    let hash = Host.sha256(archive)
    let path = Host.join([scratch, Deploying.fileName(hash)])
    Host.writeBytes(path, archive)
    (hash, path, archive->TypedArray.length, release)
  })
}

/** The archive copied in by its hash, named only once whole, so a file of that name is the same. */
let copied = (target: Machine.target, path, facts: Machine.facts, name) => {
  let into = `${facts.directory}/${name}`
  switch remote(target, `test -f ${into} && echo held || true`) {
  | Ok("held") => Ok("already there")
  | Ok(_) =>
    ran("scp", Machine.copying(target, ~path, ~into))
    ->Result.flatMap(_ => remote(target, Machine.whole(into)))
    ->Result.map(_ => `to ${into}`)
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

/**
 * The list sent with a container for the app if it holds none, and a database beside it where the
 * build declares a database or an object bucket slot and the list holds none, and those made.
 */
let listed = async (target, ~database, ~bucket, ~dry) =>
  switch describeList(target) {
  | Error(refused) => Error(refusal(refused))
  | Ok(described) =>
    let fresh = () => Host.fillRandom(Uint8Array.fromLength(32))
    let items = (into, database, object) =>
      `container ${Float.toString(into)}${database->Option.mapOr("", id =>
          ` and database ${Float.toString(id)}`
        )}${object->Option.mapOr("", id => ` and object ${Float.toString(id)}`)}`
    switch Listing.planned(described, ~fresh, ~database, ~bucket) {
    | Error(why) => Error(why)
    | Ok(Held({into, database, object})) =>
      Ok((into, database, `${items(into, database, object)} held already`))
    | Ok(Apply({list, into, database, object})) =>
      let named = `${items(into, database, object)} at generation ${Float.toString(
          list.generation,
        )}`
      if dry {
        Ok((into, database, `${named} would be sent`))
      } else {
        switch called(target, management(Apply(list)), Contracts.ManagementHeld.fromJson) {
        | Error(refused) => Error(refusal(refused))
        | Ok(_) =>
          (
            await waited(
              () => describeList(target)->Result.mapError(refusal),
              described =>
                [Some(into), database, object]
                ->Array.filterMap(id => id)
                ->Array.reduce(Ok(Some()), (all, id) =>
                  all->Result.flatMap(all =>
                    switch Listing.madeOf(described, id) {
                    | Making => Ok(None)
                    | Made => Ok(all)
                    | Failed(why) => Error(why)
                    }
                  )
                ),
            )
          )->Result.map(() => (into, database, `${named} made`))
        }
      }
    }
  }

/** The app deployed at the bundle's version, unless it already runs it, and running. */
let deployed = async (target, ~app, ~hash, ~address, ~into, ~bindings=?, ~salt, ~dry) => {
  let progress = () =>
    switch describeDeployment(target, ~salt, app) {
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
  | Ok(Waiting | Elsewhere | Failed(_)) if dry =>
    let filling = (slots, ~what) =>
      slots->Option.mapOr("", slots =>
        slots
        ->Dict.toArray
        ->Array.map(((slot, id)) => ` filling slot ${slot} with ${what} ${Float.toString(id)}`)
        ->Array.join(",")
      )
    let filled =
      bindings->Option.mapOr("", (bindings: Contracts.AppBindings.t) =>
        filling(bindings.database, ~what="database") ++ filling(bindings.bucket, ~what="bucket")
      )
    let handed = salt->Option.isSome ? ", the organization's salt handed as a secret" : ""
    Ok(`${address} would be deployed${filled}${handed}`)
  | Ok(Waiting | Elsewhere | Failed(_)) =>
    switch called(
      target,
      deployments(
        Deploy(
          switch salt {
          | Some(secrets) => Component.deploy(~app, ~hash, ~address, ~into, ~bindings?, ~secrets)
          | None => Deploying.deploy(~app, ~hash, ~address, ~into, ~bindings?)
          },
        ),
      ),
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
let appOf = (target, ~salt, app) =>
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
            : switch describeDeployment(target, ~salt, id) {
              | Error({reason: "not_found"}) => Ok(false)
              | Ok(_) => Ok(true)
              | Error(refused) => Error(refusal(refused))
              },
      )->Result.map(id => (id, "drawn, as no control draws it"))
    })
  }

/** The archive sent to the machine and deployed there, then the entry asked for the app. */
let sent = async (
  named,
  ~app,
  ~hash,
  ~path,
  ~facts: Machine.facts,
  ~binding,
  ~slots: array<Contracts.ManifestSlot.t>,
  ~salt,
  ~dry,
) => {
  let target = Machine.target(named)
  let address = Deploying.address(~directory=facts.directory, ~hash)
  let wantsDatabase = slots->Array.some(s => s.type_ == Database)
  let wantsBucket = slots->Array.some(s => s.type_ == ObjectBucket)
  let copy = dry
    ? async () => Ok("nothing copied, as --dry-run asks")
    : async () => copied(target, path, facts, Deploying.fileName(hash))
  let answered = await timed(
    "app",
    async () => appOf(target, ~salt, app),
    ((app, how)) => `${Ids.Id.text(app)}, ${how}`,
  )
  ->after(((app, _)) =>
    Deploying.held(
      ~copy=() => timed("copy", copy, said => said),
      ~deploy=() =>
        timed(
          "list",
          () => listed(target, ~database=wantsDatabase, ~bucket=wantsBucket, ~dry),
          ((_, _, said)) => said,
        )->after(((into, database, _)) =>
          timed(
            "deploy",
            () =>
              deployed(
                target,
                ~app,
                ~hash,
                ~address,
                ~into,
                ~bindings=?Deploying.bindings(slots, ~app, ~database?),
                ~salt,
                ~dry,
              ),
            said => said,
          )
        ),
      ~remove=() =>
        timed(
          "archive",
          async () =>
            dry
              ? Ok("nothing removed, as --dry-run asks")
              : remote(
                  target,
                  Machine.removeArchive(~directory=facts.directory, ~version=hash),
                )->Result.map(_ => "removed, the deployment holding its own"),
          said => said,
        ),
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
  ~release: Bundle.release,
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
    switch await Control.put(
      control,
      ~kinds=?release.kinds,
      ~ingress=?release.ingress,
      Host.readBytes(path),
    ) {
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
        await timed(
          "answer",
          () => Control.asked(control, ~ingress=release.ingress),
          _ => "the declared ingress checked",
        )
      )->Result.map(answer => Some((app, answer)))
    | Some(_) | None => Ok(None)
    }
  )
  answered->Result.map(answer =>
    answer->Option.forEach(((app, answer)) => {
      Console.log(answer)
      Control.messages(~ingress=release.ingress, ~app, ~binding)->Array.forEach(Console.log)
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
  switch Ids.Id.ofTokenText(facts.binding) {
  | Some(id) => Ok((facts, id))
  | None => Error(`the binding's token names ${facts.binding}, no binding's id`)
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
  // The salt master is read once and taken out of the environment, so no child process inherits it.
  let master = Host.env->Dict.get(Component.masterVariable)
  Host.env->Dict.delete(Component.masterVariable)
  let started = Date.now()
  switch Arguments.parse(Host.argv->Array.slice(~start=2)) {
  | Error(why) =>
    Console.error(`deploy: ${why}`)
    Host.setExitCode(Host.process, 2)
  | Ok({target: named, forget: Some(app), dry}) =>
    await onControl(named, "forget", control => forgotten(control, ~app, ~dry))
  | Ok({target: named, retire: Some(app), dry}) =>
    if Control.origin(named) != None {
      await onControl(named, "retire", control => retired(control, ~app, ~dry))
    } else {
      let target = Machine.target(named)
      switch Retiring.run(~app, ~dry, ~ask=envelope =>
        remote(target, Machine.call(envelope), ~input=JSON.stringify(envelope))
      ) {
      | Ok() => ()
      | Error(_) => Host.setExitCode(Host.process, 1)
      }
    }
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
  | Ok({component: Some(_), organization})
    if Component.secrets(~master, ~organization)->Result.isError =>
    Component.secrets(~master, ~organization)
    ->Result.mapError(why => Console.error(`deploy: ${why}`))
    ->ignore
    Host.setExitCode(Host.process, 2)
  | Ok({
      directory,
      target: named,
      app,
      binding,
      secrets,
      network,
      ingress,
      component,
      organization,
      dry,
    }) =>
    let secrets = secretsOf(secrets)->Result.getOr(dict{})
    // A component's salt is derived once, its master read here and kept no further.
    let salt = switch component {
    | None => None
    | Some(_) =>
      switch Component.secrets(~master, ~organization) {
      | Ok(held) => Some(held)
      | Error(_) => None
      }
    }
    let directory = Host.absolute(directory)
    let scratch = Host.makeTemporary(Host.join([Host.temporary(), "deploy-"]))
    let result = await timed(
      "build",
      async () => built(directory, Host.join([scratch, "out"]), ~ingress),
      ((_, release: Bundle.release, _)) =>
        release.kinds->Option.mapOr("wrangler's bundle", kinds =>
          `wrangler's bundle, declared ${kinds->Array.map(k => (k :> string))->Array.join(", ")}`
        ),
    )
    ->after(built =>
      timed(
        "pack",
        async () => packed(built, scratch),
        ((hash, _, size, release: Bundle.release)) => {
          let declared = [
            ...release.functions
            ->Option.getOr([])
            ->Array.map(f =>
              `function ${f.name} ${JSON.stringify(Contracts.FunctionKind.toJson(f.kind))}`
            ),
            ...release.slots
            ->Option.getOr([])
            ->Array.map(s =>
              `slot ${s.name} ${JSON.stringify(Contracts.SlotType.toJson(s.type_))}`
            ),
          ]->Array.join(", ")
          `${Int.toString(size)} bytes, version ${Envelope.Hex.encode(hash)}${declared == ""
              ? ""
              : `, declaring ${declared}`}`
        },
      )
    )
    ->after(((hash, path, _, release)) =>
      switch deployingOf(named, binding) {
      | Some(Ok(_)) if release.slots->Option.getOr([])->Array.length > 0 =>
        timed(
          "slots",
          async () => Error(`a control fills no slot yet, and ${named} is one`),
          _ => "",
        )
      | Some(Ok((control, binding))) =>
        throughControl(control, ~app, ~binding, ~hash, ~path, ~release, ~secrets, ~network, ~dry)
      | Some(Error(why)) => Promise.resolve(Error(why))
      | None =>
        timed(
          "ask",
          async () =>
            remote(Machine.target(named), Machine.facts)
            ->Result.flatMap(Machine.readFacts)
            ->Result.flatMap(tokenBinding),
          ((_, binding)) => `binding ${Ids.Id.text(binding)}`,
        )->after(((facts, binding)) =>
          sent(
            named,
            ~app,
            ~hash,
            ~path,
            ~facts,
            ~binding,
            ~slots=release.slots->Option.getOr([]),
            ~salt,
            ~dry,
          )
        )
      }
    )
    Host.remove(scratch, {recursive: true, force: true})
    let took = ((Date.now() -. started) /. 1000.)->Float.toFixed(~digits=1)
    switch result {
    | Ok() => Console.log(`deploy: ${directory} on ${named}, ${took}s in all`)
    | Error(_) => Host.setExitCode(Host.process, 1)
    }
  }
}

let grantMain = async bearer => {
  let parsed =
    bearer == ""
      ? Error("CONTROL_PRODUCTION_DEPLOY is empty")
      : Arguments.grant(Host.argv->Array.slice(~start=2))
  switch parsed {
  | Error(why) =>
    Console.error(`deploy: ${why}`)
    Host.setExitCode(Host.process, 2)
  | Ok((given, expected, candidate)) =>
    switch Control.origin(given.target)->Option.getOr(Error("grant target is invalid")) {
    | Error(_) =>
      Console.error("deploy: grant target is invalid")
      Host.setExitCode(Host.process, 2)
    | Ok(origin) =>
      let scratch = Host.makeTemporary(Host.join([Host.temporary(), "deploy-grant-"]))
      let environment = dict{}
      ["PATH", "HOME", "TMPDIR"]->Array.forEach(name =>
        Host.env->Dict.get(name)->Option.forEach(value => environment->Dict.set(name, value))
      )
      let run = async () => {
        let bundled =
          built(
            Host.absolute(given.directory),
            Host.join([scratch, "out"]),
            ~ingress=None,
            ~environment,
          )->Result.flatMap(built => packed(built, scratch))
        switch bundled {
        | Error(_) => Error("grant local bundle failed")
        | Ok(_) if given.dry => Ok()
        | Ok((_, path, _, _)) =>
          await Grant.deploy(
            {origin, bearer, fetch: Web.fetch},
            ~artifact=Host.readBytes(path),
            ~expected,
            ~candidate,
          )
        }
      }
      let result = switch await run() {
      | exception JsExn(_) => Error("grant deployment failed")
      | result => result
      }
      Host.remove(scratch, {recursive: true, force: true})
      switch result {
      | Ok() =>
        Console.log(
          given.dry
            ? "deploy: grant bundle built, nothing sent"
            : "deploy: grant deployment digest version and candidate confirmed",
        )
      | Error(why) =>
        Console.error(`deploy: ${why}`)
        Host.setExitCode(Host.process, 1)
      }
    }
  }
}

switch Host.env->Dict.get(Grant.variable) {
| Some(bearer) => await grantMain(bearer)
| None => await main()
}
