/***
 * `node src/main.res.mjs <contracts.json> <the library's generated/>`, as `mise run generate` runs
 * it, writing `contracts.res` and formatting it.
 */
let refuse = reason => {
  Console.error(`envelope-generator: ${reason}`)
  Host.exit(1)
}

switch Host.argv->Array.slice(~start=2) {
| [contracts, generated] =>
  let text = try Ok(Host.readFileSync(contracts)) catch {
  | JsExn(e) => Error(e->JsExn.message->Option.getOr("not read"))
  }
  switch text
  ->Result.mapError(why => `${contracts}: ${why}`)
  ->Result.flatMap(text =>
    Generate.read(text)
    ->Result.flatMap(Generate.rescript)
    ->Result.mapError(({at, expected}) => `${contracts}, at ${at}: ${expected}`)
  ) {
  | Ok(source) =>
    let path = `${generated}/contracts.res`
    Host.mkdirSync(generated, {recursive: true})
    Host.writeFileSync(path, source)
    let formatted = Host.spawnSync("rescript", ["format", path], {stdio: "inherit"})
    if formatted.status->Nullable.toOption != Some(0) {
      refuse(`${path}: not formatted by rescript format`)
    }
  | Error(reason) => refuse(reason)
  }
| _ => refuse("node src/main.res.mjs <contracts.json> <the library's generated/>")
}
