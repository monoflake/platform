/***
 * `Deploying.held` over a machine's archives kept as a set, read from the shell `Machine` writes.
 */
open Node

let holding = () => {
  let held = Set.make()
  let shell = command =>
    switch command->String.split(" ")->Array.filter(word => word != "--") {
    | ["mv", _, into] => held->Set.add(into)
    | ["rm", "-f", path] => held->Set.delete(path->String.replaceAll("'", ""))->ignore
    | _ => JsError.throwWithMessage(`no fixture for ${command}`)
    }
  (held, shell)
}

let version = byte => Uint8Array.fromLength(32)->TypedArray.fillAll(byte)

let deployed = async (shell, version, ~deploy) =>
  await Deploying.held(
    ~copy=async () => Ok(shell(Machine.whole(`/held/${Deploying.fileName(version)}`))),
    ~deploy,
    ~remove=async () => Ok(shell(Machine.removeArchive(~directory="/held", ~version))),
  )

testAsync("an app redeployed at a new version leaves no archive", async () => {
  let (held, shell) = holding()
  let answered = async () => Ok()
  deepEqual(await deployed(shell, version(1), ~deploy=answered), Ok())
  deepEqual(held->Set.size, 0)
  deepEqual(await deployed(shell, version(2), ~deploy=answered), Ok())
  deepEqual(held->Set.size, 0)
})

testAsync("a deployment that fails keeps its archive for the next try", async () => {
  let (held, shell) = holding()
  let failed = await deployed(shell, version(3), ~deploy=async () => Error("refused"))
  deepEqual(failed, Error("refused"))
  deepEqual(held->Set.size, 1)
})
