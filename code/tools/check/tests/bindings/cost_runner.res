/** The cost tests run independently of the control's work status. */
type url
@new external url: (string, string) => url = "URL"
@val external importMetaUrl: string = "import.meta.url"
@module("node:url") external pathOf: url => string = "fileURLToPath"
@module("node:process") external executable: string = "execPath"
@module("node:process") external environment: dict<string> = "env"

type options = {cwd: string, stdio: string, env: dict<string>}
type spawned = {status: Nullable.t<int>}
@module("node:child_process")
external spawn: (string, array<string>, options) => spawned = "spawnSync"

let run = () => {
  let root = url("../../../../../", importMetaUrl)->pathOf
  let env = Dict.copy(environment)
  env->Dict.delete("NODE_TEST_CONTEXT")
  let options = {cwd: root, stdio: "inherit", env}
  let step = (command, arguments) =>
    spawn(command, arguments, options).status->Nullable.toOption->Option.getOr(1)
  let rescript = `${root}node_modules/.bin/rescript`
  // The control builds against libraries a tool writes, so they are written first.
  let written = switch step(rescript, ["build"]) {
  | 0 => step(executable, ["model/generate.res.mjs"])
  | code => code
  }
  switch written {
  | 0 =>
    switch step(rescript, ["build", "code/products/control"]) {
    | 0 => step(executable, ["--test", "code/products/control/tests/state/state_cost_test.res.mjs"])
    | code => code
    }
  | code => code
  }
}
