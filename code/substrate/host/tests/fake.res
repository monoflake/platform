/*** A fake driver answering `describe` as the deployments samples' steps leave each deployment. */
open Sample

/** The address the fake reports for what a step captures by name. */
let addressOf = name => `https://deployment.invalid/${name}`

/** Each deployment's state by its runs, written as JSON. */
type t = dict<Contracts.DeploymentState.t>

let make = (): t => dict{}

let keyOf = runs => runs->Contracts.DeploymentRuns.toJson->JSON.stringify

/** The state an answer's expected state leaves, none where the sample leaves it to the driver. */
let stateOf = (json): Contracts.DeploymentState.t =>
  switch member(json, "name")->Option.map(string) {
  | Some("running") =>
    switch json->at(["address"])->placeholder("$capture") {
    | Some(name) => Running({address: addressOf(name), runtime: Workers, isolation: [Isolate]})
    | None =>
      JsError.throwWithMessage(`${JSON.stringify(json)}: running, its address captured by no name`)
    }
  | Some("stopped") => Stopped
  | Some(name) => JsError.throwWithMessage(`${name}: no state a sample leaves`)
  // `$any` while a deployment is made or resumed, until a describe shows it running.
  | None => Making
  }

/** What a call step leaves of its deployment, as the step expects its driver to answer. */
let step = (fake: t, step) => {
  let key = step->at(["input", "runs"])->runs->keyOf
  let expect = step->at(["expect"])
  switch (member(expect, "output"), member(expect, "failure")) {
  | (Some(output), None) =>
    switch member(output, "state") {
    | Some(state) => fake->Dict.set(key, stateOf(state))
    | None => fake->Dict.delete(key)
    }
  | (None, Some(_)) =>
    if expect->at(["reason"])->string == "not_found" {
      fake->Dict.delete(key)
    }
  | _ => JsError.throwWithMessage(`${JSON.stringify(expect)}: no one answer`)
  }
}

/** The driver over what the fake holds, answering `not_found` for what it does not. */
let driver = (fake: t): Handed.driver => {
  describe: async ({runs}) =>
    switch fake->Dict.get(keyOf(runs)) {
    | Some(state) => Contracts.Answer.Success({runs, version: Uint8Array.fromLength(32), state})
    | None =>
      Contracts.Answer.Error({
        failure: Rejected,
        reason: "not_found",
        message: "Nothing of that name or id exists",
      })
    },
}
