/***
 * `mise run update`, in order: the flake's inputs moved to their branches' heads on a copy, Nix
 * reading a flake from git's index alone, `docs/lessons/building.md`, and its lock copied back;
 * then the pins tool, `code/tools/pins`, built and run on workerd's image and the flake. What the
 * verb is owed is the workspace's `docs/repos.md`, "What a repository's task owes the verb".
 */
type spawned = {status: Nullable.t<int>, stdout: string, stderr: string}
type options = {encoding?: string, stdio?: string}
@module("node:child_process")
external spawnSync: (string, array<string>, options) => spawned = "spawnSync"
@module("node:fs") external copyFileSync: (string, string) => unit = "copyFileSync"
@module("node:fs") external mkdtempSync: string => string = "mkdtempSync"
@module("node:fs") external realpathSync: string => string = "realpathSync"
@module("node:os") external tmpdir: unit => string = "tmpdir"
@module("node:process") external exit: int => unit = "exit"
@val @scope(("process", "env")) external dryRun: Nullable.t<string> = "usage_dry_run"
@val @scope(("process", "env")) external major: Nullable.t<string> = "usage_major"

let dry = dryRun->Nullable.toOption == Some("true")

/** One step run, what it printed returned, and the update stopped where it fails. */
let step = (command, args) => {
  let done = spawnSync(command, args, {encoding: "utf8"})
  if done.status->Nullable.toOption != Some(0) {
    Console.error(done.stdout ++ done.stderr)
    exit(1)
  }
  done.stdout ++ done.stderr
}

if major->Nullable.toOption == Some("true") {
  Console.log(
    "update: --major is refused; nothing here has a range to cross, and a newer NixOS release is an edit to flake.nix",
  )
  // Refused by policy, so nothing to put back, the workspace's `docs/repos.md`.
  exit(0)
} else {
  let copy = realpathSync(mkdtempSync(`${tmpdir()}/platform-update-`))
  ["flake.nix", "flake.lock"]->Array.forEach(file => copyFileSync(file, `${copy}/${file}`))
  let moved = step("nix", ["flake", "update", "--flake", `path:${copy}`])->String.trim
  Console.log(`Flake inputs:\n${moved == "" ? "  each at its branch's head" : moved}`)
  if !dry {
    copyFileSync(`${copy}/flake.lock`, "flake.lock")
  }
  step("rescript", ["build", "code/tools/pins"])->ignore
  let pinned = spawnSync(
    "node",
    [
      "code/tools/pins/src/main.res.mjs",
      "code/substrate/driver/machine/images/workerd/Dockerfile",
      "pnpm-workspace.yaml",
      "flake.nix",
      ...dry ? ["--dry-run"] : [],
    ],
    {stdio: "inherit"},
  )
  if pinned.status->Nullable.toOption != Some(0) {
    exit(1)
  }
}
