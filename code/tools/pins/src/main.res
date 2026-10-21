/***
 * `node src/main.res.mjs <Dockerfile> <pnpm-workspace.yaml> <flake.nix> [--dry-run]`, as platform's
 * `update` runs it: workerd's pin moved to what `Pin.choose` takes, each architecture's download
 * hashed, and the Dockerfile written unless dry; what is held back, and a NixOS release newer than
 * the flake follows, named either way.
 */
let refuse = reason => {
  Console.error(`pins: ${reason}`)
  Host.exit(1)
}

// The packages as `pin.resi` names them, by Docker's architecture; amd64's versions are the ones read.
let packages = dict{"amd64": "workerd-linux-64", "arm64": "workerd-linux-arm64"}
let registryOf = name => `https://registry.npmjs.org/@cloudflare/${name}`
let tarball = (name, version) => `${registryOf(name)}/-/${name}-${version}.tgz`

let readFile = path =>
  try Ok(Host.readFileSync(path)) catch {
  | JsExn(e) => Error(`${path}: ${e->JsExn.message->Option.getOr("not read")}`)
  }

let run = (command, args) => {
  let done = Host.spawnSync(command, args, {encoding: "utf8"})
  done.status->Nullable.toOption == Some(0)
    ? Ok(done.stdout)
    : Error(`${command} ${args->Array.join(" ")}: ${done.stderr}`)
}

let fetched = async (url, read) =>
  switch await Host.fetch(url) {
  | response if response->Host.ok => Ok(await read(response))
  | response => Error(`${url} answered ${response->Host.status->Int.toString}`)
  | exception JsExn(e) => Error(`${url}: ${e->JsExn.message->Option.getOr("not reached")}`)
  }

/** One download's SHA-256 in hex, as `ADD --checksum=sha256:` takes it. */
let hashed = async url =>
  (await fetched(url, Host.arrayBuffer))->Result.map(bytes =>
    Host.createHash("sha256")->Host.update(Uint8Array.fromBuffer(bytes))->Host.digest("hex")
  )

/** Each architecture's hash of `version`, for the architectures the file pins. */
let hashes = async (pinned: Pin.pin, version) => {
  let found = Dict.make()
  let failed = ref(None)
  for index in 0 to pinned.hashes->Dict.keysToArray->Array.length - 1 {
    let architecture = pinned.hashes->Dict.keysToArray->Array.getUnsafe(index)
    if failed.contents == None {
      switch packages->Dict.get(architecture) {
      | None => failed := Some(`no npm package is known for ${architecture}`)
      | Some(name) =>
        switch await hashed(tarball(name, version)) {
        | Ok(hash) => found->Dict.set(architecture, hash)
        | Error(why) => failed := Some(why)
        }
      }
    }
  }
  switch failed.contents {
  | None => Ok(found)
  | Some(why) => Error(why)
  }
}

let workerd = async (file, workspace, ~dry) => {
  let text = readFile(file)
  let pinned = text->Result.flatMap(Pin.read)->Result.mapError(why => `${file}: ${why}`)
  let delay =
    readFile(workspace)->Result.flatMap(Pin.delay)->Result.mapError(why => `${workspace}: ${why}`)
  switch (text, pinned, delay) {
  | (Ok(text), Ok(pinned), Ok(delay)) =>
    switch (await fetched(registryOf("workerd-linux-64"), Host.text))->Result.flatMap(
      Pin.registry,
    ) {
    | Ok(registry) =>
      let {take, held} = Pin.choose(registry, ~delay, ~now=Date.now())
      Console.log("workerd:")
      let moved = switch take {
      | Some(version) if version != pinned.version =>
        Console.log(`  ${pinned.version} -> ${version}`)
        dry
          ? Ok()
          : (await hashes(pinned, version))
            ->Result.flatMap(hashes => Pin.write(text, {version, hashes}))
            ->Result.map(written => Host.writeFileSync(file, written))
      | Some(_) =>
        Console.log(`  ${pinned.version}, the newest past the delay`)
        Ok()
      | None =>
        Console.log(`  ${pinned.version}, since no version is past the delay`)
        Ok()
      }
      if held != [] {
        Console.log(
          `  held back by minimumReleaseAge, ${delay->Int.toString} minutes: ${held->Array.join(
              ", ",
            )}`,
        )
      }
      moved
    | Error(why) => Error(why)
    }
  | (Error(why), _, _) | (_, Error(why), _) | (_, _, Error(why)) => Error(why)
  }
}

/** A NixOS release newer than the flake follows, which only an edit to flake.nix crosses. */
let beyond = flake =>
  readFile(flake)
  ->Result.flatMap(Pin.follows)
  ->Result.mapError(why => `${flake}: ${why}`)
  ->Result.flatMap(follows =>
    // A read of a remote, touching no repository, which is all "jj, never git" guards.
    run(
      "git",
      ["ls-remote", "--heads", "https://github.com/NixOS/nixpkgs", "refs/heads/nixos-*"],
    )->Result.map(heads => {
      Console.log("Beyond its bounds:")
      switch Pin.release(heads, ~follows) {
      | Some(newer) =>
        Console.log(`  ${newer}, newer than ${follows}; crossing it is an edit to flake.nix`)
      | None => Console.log(`  nothing: ${follows} is the newest NixOS release`)
      }
    })
  )

switch Host.argv->Array.slice(~start=2) {
| [file, workspace, flake] | [file, workspace, flake, "--dry-run"] =>
  switch (
    await workerd(file, workspace, ~dry=Host.argv->Array.includes("--dry-run"))
  )->Result.flatMap(() => beyond(flake)) {
  | Ok() => ()
  | Error(why) => refuse(why)
  }
| _ => refuse("node src/main.res.mjs <Dockerfile> <pnpm-workspace.yaml> <flake.nix> [--dry-run]")
}
