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
  let root = url("../../../", importMetaUrl)->pathOf
  let env = Dict.copy(environment)
  env->Dict.delete("NODE_TEST_CONTEXT")
  let options = {cwd: root, stdio: "inherit", env}
  let build = spawn(
    `${root}node_modules/.bin/rescript`,
    ["build", "code/products/control"],
    options,
  )
  switch build.status->Nullable.toOption {
  | Some(0) =>
    spawn(
      executable,
      ["--test", "code/products/control/tests/state/state_cost_test.res.mjs"],
      options,
    ).status
    ->Nullable.toOption
    ->Option.getOr(1)
  | Some(code) => code
  | None => 1
  }
}
