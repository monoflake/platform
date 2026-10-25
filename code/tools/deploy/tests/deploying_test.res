/***
 * `Deploying` held to RFC vr5lw and RFC n0o4l, the deploy written as the contract reads it, the
 * entry's host, and how far a deployment has come.
 */
open Node

module Contracts = Envelope.Contracts

let hash = Uint8Array.fromArray(Array.make(~length=32, 0xab))
let other = Uint8Array.fromArray(Array.make(~length=32, 0x01))

test("the artifact's address is its hash in the driver's directory", () =>
  deepEqual(
    Deploying.address(~directory="/var/lib/driver-machine/artifacts", ~hash),
    `file:///var/lib/driver-machine/artifacts/${String.repeat("ab", 32)}.tar`,
  )
)

test("a deploy is read back by the contract as the bundle of modules it was written as", () => {
  let address = Deploying.address(~directory="/d", ~hash)
  let written = Contracts.DeploymentDeploy.toJson(
    Deploying.deploy(~app=4275878552., ~hash, ~address, ~into=2.),
  )
  deepEqual(
    written,
    JSON.parseOrThrow(
      `{
      "runs": {"name": "app", "id": 4275878552},
      "version": "${String.repeat("ab", 32)}",
      "form": "modules",
      "isolation": ["isolate"],
      "artifact": {"address": "${address}", "hash": "${String.repeat("ab", 32)}"},
      "footing": "https://footing.invalid",
      "secrets": {},
      "network": [],
      "into": 2
    }`,
    ),
  )
  ok(Contracts.DeploymentDeploy.fromJson(written)->Result.isOk)
})

test("the entry's host is the app's id in 8 hex digits, then the binding's", () => {
  deepEqual(Deploying.host(~app=1., ~binding=1.), "00000001.b00000001")
  deepEqual(Deploying.host(~app=169552957., ~binding=4275878552.), "0a1b2c3d.bfedcba98")
})

test("a deployment is running, waiting, elsewhere or failed, by its version and state", () => {
  let at = (version, state): Contracts.DeploymentDescribed.t => {
    runs: App({id: 1.}),
    version,
    state,
  }
  let running: Contracts.DeploymentState.t = Running({
    address: "a",
    runtime: Workerd,
    isolation: [Isolate],
  })
  deepEqual(Deploying.progress(at(hash, running), hash), Running)
  deepEqual(Deploying.progress(at(hash, Making), hash), Waiting)
  deepEqual(Deploying.progress(at(other, running), hash), Elsewhere)
  deepEqual(Deploying.progress(at(hash, Failed({reason: "malformed"})), hash), Failed("malformed"))
  ok(
    switch Deploying.progress(at(hash, Stopped), hash) {
    | Failed(_) => true
    | Running | Waiting | Elsewhere => false
    },
  )
})
