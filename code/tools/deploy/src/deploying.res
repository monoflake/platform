module Contracts = Envelope.Contracts

let fileName = hash => `${Envelope.Hex.encode(hash)}.tar`

let address = (~directory, ~hash) => `file://${directory}/${fileName(hash)}`

let deploy = (~app, ~hash, ~address, ~into, ~bindings=?): Contracts.DeploymentDeploy.t => {
  runs: App({id: app}),
  version: hash,
  form: Modules,
  isolation: [Isolate],
  artifact: {address, hash},
  // No footing is built yet, so the address is one that answers nothing.
  footing: "https://footing.invalid",
  secrets: dict{},
  network: [],
  into,
  ?bindings,
}

let bucketId = (~app, ~slot) => {
  let name = Bytes.utf8(slot)
  let input = Uint8Array.fromLength(4 + TypedArray.length(name))
  // Big-endian bytes by float arithmetic, as a uint32 does not fit the language's int.
  let byte = place =>
    Float.toInt(Math.floor(app /. place) -. Math.floor(app /. place /. 256.) *. 256.)
  input->Bytes.copyInto(
    Uint8Array.fromArray([byte(16777216.), byte(65536.), byte(256.), byte(1.)]),
    0,
  )
  input->Bytes.copyInto(name, 4)
  let hash = Keys.Hash.plain(input)
  [0, 1, 2, 3]->Array.reduce(0., (sum, at) =>
    sum *. 256. +. Int.toFloat(hash->TypedArray.get(at)->Option.getOr(0))
  )
}

let bindings = (slots: array<Contracts.ManifestSlot.t>, ~app, ~database=?, ~records=?) => {
  let named = type_ => slots->Array.filter(s => s.type_ == type_)
  let filled = (slots, id) =>
    switch slots->Array.filterMap((s: Contracts.ManifestSlot.t) =>
      id(s.name)->Option.map(id => (s.name, id))
    ) {
    | [] => None
    | pairs => Some(Dict.fromArray(pairs))
    }
  // Records given is a compute deploy, its `records` slot its own item and the rest the apps' one.
  let databaseOf = slot =>
    switch records {
    | Some(records) if slot == "records" => Some(records)
    | Some(_) | None => database
    }
  let databases = filled(named(Database), databaseOf)
  let buckets = filled(named(ObjectBucket), slot => Some(bucketId(~app, ~slot)))
  switch (databases, buckets) {
  | (None, None) => None
  | (Some(database), None) => Some(({database: database}: Contracts.AppBindings.t))
  | (None, Some(bucket)) => Some(({bucket: bucket}: Contracts.AppBindings.t))
  | (Some(database), Some(bucket)) => Some(({database, bucket}: Contracts.AppBindings.t))
  }
}

let of_ = (app): Contracts.DeploymentOf.t => {runs: App({id: app})}

let host = (~app, ~binding) => `${Ids.Id.text(app)}.b${Ids.Id.text(binding)}`

type progress = Running | Waiting | Elsewhere | Failed(string)

let progress = (described: Contracts.DeploymentDescribed.t, version) =>
  if Envelope.Hex.encode(described.version) != Envelope.Hex.encode(version) {
    Elsewhere
  } else {
    switch described.state {
    | Running(_) => Running
    | Making => Waiting
    | Stopped => Failed("stopped, as deployments stop left it")
    | Failed({reason, ?message}) => Failed(message->Option.mapOr(reason, m => `${reason}, ${m}`))
    }
  }

/** An archive held on the machine only while a deployment is made of it, kept if that fails. */
let held = async (~copy, ~deploy, ~remove) =>
  switch await copy() {
  | Error(why) => Error(why)
  | Ok(_) =>
    switch await deploy() {
    | Error(why) => Error(why)
    | Ok(_) => (await remove())->Result.map(_ => ())
    }
  }
