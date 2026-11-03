module Contracts = Envelope.Contracts

let variable = "CONTROL_PRODUCTION_DEPLOY"

type t = {
  origin: string,
  bearer: string,
  fetch: (string, Web.init) => promise<Web.response>,
}

let call = async (grant, operation, data) => {
  let envelope = Contracts.Interface.DeploymentGrants.toJson({call: operation, capabilities: []})
  let name =
    envelope
    ->JSON.Decode.object
    ->Option.flatMap(o => o->Dict.get("operation"))
    ->Option.flatMap(JSON.Decode.string)
    ->Option.getOr("")
  switch await grant.fetch(
    `${grant.origin}/deployment_grants/${name}`,
    {
      method: "POST",
      headers: dict{
        "authorization": `Bearer ${grant.bearer}`,
        "content-type": "application/json",
        "accept": "application/json",
      },
      body: JSON.stringify(envelope),
      redirect: "error",
    },
  ) {
  | exception JsExn(_) => Error(`grant ${name} did not answer`)
  | response =>
    switch await response->Web.text {
    | exception JsExn(_) => Error(`grant ${name} response could not be read`)
    | body =>
      if response->Web.status != 200 {
        Error(`grant ${name} refused`)
      } else {
        Machine.answer(body, data)->Result.mapError(_ => `grant ${name} refused or malformed`)
      }
    }
  }
}

let status = grant => call(grant, Status({}), Contracts.DeploymentGrantDescribed.fromJson)

let matches = (described: Contracts.DeploymentGrantDescribed.t, digest, candidate) =>
  Envelope.Hex.encode(described.digest) == Envelope.Hex.encode(digest) &&
    described.candidate == candidate

let rec running = async (grant, ~digest, ~candidate, ~version, ~left=300) =>
  switch await status(grant) {
  | Error(why) => Error(why)
  | Ok(described) if described.version < version && left > 0 =>
    await Host.sleep(200)
    await running(grant, ~digest, ~candidate, ~version, ~left=left - 1)
  | Ok(described) if described.version == version && matches(described, digest, candidate) => Ok()
  | Ok(_) => Error("grant status does not match the deployed digest version and candidate")
  }

let deploy = async (grant, ~artifact, ~expected, ~candidate) => {
  let digest = Host.sha256(artifact)
  switch await call(grant, Upload({artifact, digest}), Contracts.DeploymentGrantArtifact.fromJson) {
  | Error(why) => Error(why)
  | Ok(held) if Envelope.Hex.encode(held.digest) != Envelope.Hex.encode(digest) =>
    Error("grant upload returned a different digest")
  | Ok(_) =>
    switch await call(
      grant,
      Deploy({digest, expected, candidate}),
      Contracts.DeploymentGrantDescribed.fromJson,
    ) {
    | Error(why) => Error(why)
    | Ok(described)
      if described.version != expected +. 1. || !matches(described, digest, candidate) =>
      Error("grant deploy returned a different digest version or candidate")
    | Ok(_) => await running(grant, ~digest, ~candidate, ~version=expected +. 1.)
    }
  }
}
