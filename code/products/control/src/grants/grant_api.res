module C = Envelope.Contracts
module I = C.Interface.DeploymentGrants
module Calls = Serve.Calls
module Context = Grant_context

let denied = Calls.Refused({reason: "denied", message: None})
let refused = reason => Calls.Refused({reason, message: None})
let output = (value, toJson, toCbor) => Calls.Output(Calls.output(value, ~toJson, ~toCbor))
let described = value =>
  output(value, C.DeploymentGrantDescribed.toJson, C.DeploymentGrantDescribed.toCbor)
let lifetime = 180. *. 86400000.

let mint = async (t: Context.t, input: C.DeploymentGrantMint.t) => {
  let expires = switch input.policy {
  | Deploy({expires}) | Health({expires}) => expires
  }
  let now = t.store.now()
  if !(expires > now && expires <= now +. lifetime) {
    refused("invalid")
  } else {
    let policy = switch input.policy {
    | Health(_) =>
      Ok(C.DeploymentGrantPolicy.Health({control: await Web.sha256(Web.utf8(t.origin))}))
    | Deploy({app}) =>
      switch await t.state.deployment(app) {
      | None => Error("not_found")
      | Some(d) =>
        switch await t.state.binding(d.binding) {
        | Some(b) if await Context.initialized(t, d, b) =>
          await Grant_store.initialize(
            t.store,
            app,
            d.release,
            JSON.stringify(C.DeploymentCandidate.toJson(Context.emptyCandidate)),
          )
          Ok(
            C.DeploymentGrantPolicy.Deploy({
              app,
              binding: b.id,
              organization: b.organization,
              ingress: Grant_archive.ingressText(d.ingress),
            }),
          )
        | Some(_) | None => Error("unbound")
        }
      }
    }
    switch policy {
    | Error(reason) => refused(reason)
    | Ok(policy) =>
      let grant = Envelope.Base64url.encode(t.random(16))
      let bearer = `dg1.${grant}.${Envelope.Base64url.encode(t.random(32))}`
      await Grant_store.insert(
        t.store,
        {
          grant,
          verifier: Envelope.Hex.encode(await Web.sha256(Web.utf8(bearer))),
          expires,
          revoked: 0,
          policy: JSON.stringify(C.DeploymentGrantPolicy.toJson(policy)),
        },
        ~app=switch policy {
        | Deploy({app}) => Some(app)
        | Health(_) => None
        },
      )
      await Grant_staging.sweep(t)
      output(
        ({grant, bearer: Web.utf8(bearer), expires}: C.DeploymentGrantMinted.t),
        C.DeploymentGrantMinted.toJson,
        C.DeploymentGrantMinted.toCbor,
      )
    }
  }
}

let revoke = async (t: Context.t, input: C.DeploymentGrantId.t) =>
  if await Grant_store.revoke(t.store, input.grant) {
    await Grant_staging.revoked(t, input.grant)
    await Grant_staging.sweep(t)
    output(input, C.DeploymentGrantId.toJson, C.DeploymentGrantId.toCbor)
  } else {
    refused("not_found")
  }

let upload = async (t: Context.t, proof, input: C.DeploymentGrantUpload.t) =>
  switch await Context.verified(t, proof) {
  | None => denied
  | Some(row) =>
    switch await Context.fixed(t, row) {
    | None => denied
    | Some((d, _)) =>
      let size = input.artifact->TypedArray.length
      if !Grant_archive.valid(input.artifact, ~ingress=Grant_archive.ingressText(d.ingress)) {
        refused("invalid")
      } else if size > 33554432 {
        refused("too_large")
      } else if !Access.equal(await Web.sha256(input.artifact), input.digest) {
        refused("hash_mismatch")
      } else {
        switch await Context.verified(t, proof) {
        | None => denied
        | Some(current) =>
          switch await Context.fixed(t, current) {
          | None => denied
          | Some(_) =>
            let digest = Envelope.Hex.encode(input.digest)
            let expires = Math.min(row.expires, t.store.now() +. 3600000.)
            await Grant_staging.sweep(t)
            if !(await Grant_store.room(t.store, row.grant, digest)) {
              refused("too_large")
            } else {
              await t.artifacts.put(Context.stagingKey(row.grant, digest), input.artifact)
              if (
                await Grant_store.stage(
                  t.store,
                  row.grant,
                  digest,
                  Int.toFloat(size),
                  expires,
                  Envelope.Base64url.encode(t.random(32)),
                )
              ) {
                output(
                  ({digest: input.digest, expires}: C.DeploymentGrantArtifact.t),
                  C.DeploymentGrantArtifact.toJson,
                  C.DeploymentGrantArtifact.toCbor,
                )
              } else {
                await t.artifacts.delete(Context.stagingKey(row.grant, digest))
                (await Context.verified(t, proof)) == None ? denied : refused("too_large")
              }
            }
          }
        }
      }
    }
  }

let status = async (t: Context.t, proof) =>
  switch await Context.verified(t, proof) {
  | None => denied
  | Some(row) =>
    switch await Context.fixed(t, row) {
    | None => denied
    | Some((d, _)) =>
      await Grant_lease.reconcile(t, d.app)
        ? (await Context.described(t, d.app))->Option.mapOr(denied, described)
        : Grant_lease.unavailable
    }
  }

let health = async (t: Context.t, proof, input: C.HealthRequest.t) =>
  switch await Context.verified(t, proof) {
  | None => denied
  | Some(row) =>
    switch Context.policyOf(row) {
    | Ok(Health(_)) if !Grant_rate.allowed(~grant=row.grant, ~now=t.store.now()) => denied
    | Ok(Health(_)) =>
      let ready = switch await t.ready() {
      | ready => t.initialized() && ready
      | exception JsExn(_) => false
      }
      output(
        ({nonce: input.nonce, state: ready ? Ready : Unavailable}: C.HealthAnswer.t),
        C.HealthAnswer.toJson,
        C.HealthAnswer.toCbor,
      )
    | Ok(Deploy(_)) | Error(_) => denied
    }
  }

let route = (t: Context.t, caller: Access.caller, ~authenticate=async () => caller) =>
  Calls.route({
    name: "deployment_grants",
    fromJson: Grant_wire.fromJson,
    fromCbor: Grant_wire.fromCbor,
    reasons: [I.mint, I.revoke, I.upload, I.deploy, I.status, I.health],
    handle: async (_, {call}) => {
      let caller = await authenticate()
      switch (caller, call) {
      | (Operator, Mint(input)) => await mint(t, input)
      | (Operator, Revoke(input)) => await revoke(t, input)
      | (DeploymentGrant(proof), Upload(input)) => await upload(t, proof, input)
      | (DeploymentGrant(proof), Deploy(input)) => await Grant_deploy.deploy(t, proof, input)
      | (DeploymentGrant(proof), Status(_)) => await status(t, proof)
      | (HealthGrant(proof), Health(input)) => await health(t, proof, input)
      | (
          Operator | Host(_) | Organization(_) | DeploymentGrant(_) | HealthGrant(_) | Nobody,
          Mint(_) | Revoke(_) | Upload(_) | Deploy(_) | Status(_) | Health(_),
        ) => denied
      }
    },
  })
