/***
 * `Component` held to RFC b8f35 and RFC ahcrp, the storage deploy's runs and the salt it is handed
 * from the master and the organization.
 */
open Node

module Contracts = Envelope.Contracts

let master = String.repeat("0123456789abcdef", 4)
let organization = 169552957.
let hash = Uint8Array.fromArray(Array.make(~length=32, 0xab))

let handed = secrets => secrets->Dict.get(Component.secretName)->Option.map(Bytes.text)

test("a storage deploy runs as the component, its id the one given, and hands its secrets", () => {
  let address = Deploying.address(~directory="/d", ~hash)
  let secrets = Dict.make()
  secrets->Dict.set("SALT", Bytes.utf8("aa"))
  let deploy = Component.deploy(~app=4275878552., ~hash, ~address, ~into=2., ~secrets)
  let written = Contracts.DeploymentDeploy.toJson(deploy)
  deepEqual(
    written->JSON.Decode.object->Option.flatMap(o => o->Dict.get("runs")),
    Some(JSON.parseOrThrow(`{"name": "component", "component": "storage", "id": 4275878552}`)),
  )
  deepEqual(
    deploy,
    {
      ...Deploying.deploy(~app=4275878552., ~hash, ~address, ~into=2.),
      runs: Component({component: "storage", id: 4275878552.}),
      secrets,
    },
  )
  deepEqual(Contracts.DeploymentDeploy.fromJson(written)->Result.map(d => d.runs), Ok(deploy.runs))
  deepEqual(
    Contracts.DeploymentOf.toJson(Component.of_(7.)),
    JSON.parseOrThrow(`{"runs": {"name": "component", "component": "storage", "id": 7}}`),
  )
})

test("a compute deploy names its component and carries no secrets of its own", () => {
  let address = Deploying.address(~directory="/d", ~hash)
  let deploy = Component.deploy(~component="compute", ~app=1., ~hash, ~address, ~into=2.)
  deepEqual(deploy.runs, Component({component: "compute", id: 1.}))
  deepEqual(deploy.secrets, None)
  deepEqual(Component.of_(~component="compute", 1.), {runs: deploy.runs})
})

test("the salt handed is keys' salt of the master and organization, 64 lowercase hex", () => {
  let expected =
    Keys.Derive.salt(
      ~master=Envelope.Hex.decode(master)->Option.getOrThrow,
      ~scope=organization,
    )->Result.getOrThrow
  switch Component.secrets(~master=Some(master), ~organization=Some(organization)) {
  | Error(why) => JsError.throwWithMessage(why)
  | Ok(secrets) =>
    deepEqual(secrets->Dict.keysToArray, ["SALT"])
    deepEqual(handed(secrets), Some(Envelope.Hex.encode(expected)))
    ok(/^[0-9a-f]{64}$/->RegExp.test(handed(secrets)->Option.getOr("")))
    ok(Component.secretName == "SALT")
  }
})

test("another organization is handed another salt, the same one the same", () => {
  let salt = id =>
    Component.secrets(~master=Some(master), ~organization=Some(id))->Result.getOrThrow->handed
  deepEqual(salt(1.), salt(1.))
  ok(salt(1.) != salt(2.))
})

test("a missing or malformed master or organization is refused naming which", () => {
  let refused = (master, organization) =>
    switch Component.secrets(~master, ~organization) {
    | Error(why) => why
    | Ok(_) => "accepted"
    }
  ok(refused(None, Some(1.))->String.includes("salt master is unset"))
  ok(refused(Some(""), Some(1.))->String.includes("salt master is unset"))
  ok(refused(Some(master), None)->String.includes("organization is missing"))
  ok(refused(Some(String.repeat("0", 63)), Some(1.))->String.includes("salt master is no 64"))
  ok(refused(Some(String.toUpperCase(master)), Some(1.))->String.includes("salt master is no 64"))
  ok(refused(Some(String.repeat("g", 64)), Some(1.))->String.includes("salt master is no 64"))
  ok(!(refused(Some("nope"), Some(1.))->String.includes(master)))
})
