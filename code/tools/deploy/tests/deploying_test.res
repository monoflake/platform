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

test("a deploy carries bindings only where given, and the contract reads them back", () => {
  let address = Deploying.address(~directory="/d", ~hash)
  let bound = switch Deploying.bindings(
    [{name: "database", type_: Database}],
    ~app=1.,
    ~database=7.,
  ) {
  | Some(bindings) => bindings
  | None => JsExn.throw("no bindings made")
  }
  let written = Contracts.DeploymentDeploy.toJson(
    Deploying.deploy(~app=1., ~hash, ~address, ~into=2., ~bindings=bound),
  )
  deepEqual(
    written->JSON.Decode.object->Option.flatMap(o => o->Dict.get("bindings")),
    Some(JSON.parseOrThrow(`{"database": {"database": 7}}`)),
  )
  ok(Contracts.DeploymentDeploy.fromJson(written)->Result.isOk)
  deepEqual(
    Contracts.DeploymentDeploy.toJson(Deploying.deploy(~app=1., ~hash, ~address, ~into=2.))
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("bindings")),
    None,
  )
})

test("each database slot is filled with the one item, and a build with none carries none", () => {
  deepEqual(
    Deploying.bindings(
      [{name: "database", type_: Database}, {name: "archive", type_: Database}],
      ~app=1.,
      ~database=3.,
    ),
    Some({database: dict{"database": 3., "archive": 3.}}),
  )
  deepEqual(Deploying.bindings([], ~app=1., ~database=3.), None)
  deepEqual(Deploying.bindings([{name: "peer", type_: App}], ~app=1., ~database=3.), None)
})

test("a bucket's id is BLAKE3 of the app's id and the slot's name, the same on every call", () => {
  deepEqual(Deploying.bucketId(~app=1., ~slot="files"), 1195018073.)
  deepEqual(Deploying.bucketId(~app=1., ~slot="files"), 1195018073.)
  deepEqual(Deploying.bucketId(~app=4275878552., ~slot="files"), 3940802388.)
})

test("a bucket's id differs for another slot or another app", () => {
  deepEqual(Deploying.bucketId(~app=1., ~slot="other"), 3802056418.)
  deepEqual(Deploying.bucketId(~app=2., ~slot="files"), 729273978.)
})

test("each object bucket slot is filled with its own id beside the database slots", () => {
  deepEqual(
    Deploying.bindings(
      [{name: "files", type_: ObjectBucket}, {name: "database", type_: Database}],
      ~app=1.,
      ~database=3.,
    ),
    Some({database: dict{"database": 3.}, bucket: dict{"files": 1195018073.}}),
  )
  deepEqual(
    Deploying.bindings([{name: "files", type_: ObjectBucket}], ~app=1.),
    Some({bucket: dict{"files": 1195018073.}}),
  )
})
