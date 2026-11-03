/***
 * The storage product deployed as a component on a machine, the organization's salt handed to it
 * as a secret derived from a master that never leaves the deploy, RFC b8f35 and RFC ahcrp.
 */
module Contracts = Envelope.Contracts

/** The environment variable the salt master is read from. */
let masterVariable = "salt-master"

/** The secret the deployment is handed the salt as. */
let secretName = "SALT"

/**
 * The secrets a storage deploy carries, the salt of `organization` from the master's 64 lowercase
 * hex digits as 64 lowercase hex under `secretName`, or which of the two is missing or malformed.
 */
let secrets = (~master, ~organization) =>
  switch (master, organization) {
  | (None | Some(""), _) => Error(`the salt master is unset, ${masterVariable} in the environment`)
  | (_, None) => Error("the organization is missing, --organization asks its 8 lowercase hex")
  | (Some(master), Some(organization)) =>
    switch (/^[0-9a-f]{64}$/->RegExp.test(master), Envelope.Hex.decode(master)) {
    | (true, Some(bytes)) =>
      switch Keys.Derive.salt(~master=bytes, ~scope=organization) {
      | Ok(salt) =>
        let held = Dict.make()
        held->Dict.set(secretName, Bytes.utf8(Envelope.Hex.encode(salt)))
        Ok(held)
      | Error(_) => Error("the organization is outside the ids a salt is derived for")
      }
    | _ => Error(`the salt master is no 64 lowercase hex, ${masterVariable} in the environment`)
    }
  }

/** The deployment's `runs` for the component with this id. */
let runs = (id): Contracts.DeploymentRuns.t => Component({component: "storage", id})

/** The component's deployment, as describe asks it. */
let of_ = (id): Contracts.DeploymentOf.t => {runs: runs(id)}

/** A deploy of the bundle as the storage component, the secrets handed it. */
let deploy = (~app, ~hash, ~address, ~into, ~bindings=?, ~secrets) => {
  ...Deploying.deploy(~app, ~hash, ~address, ~into, ~bindings?),
  runs: runs(app),
  secrets,
}
