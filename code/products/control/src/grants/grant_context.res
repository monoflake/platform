module C = Envelope.Contracts

type t = {
  store: Grant_store.t,
  state: State.t,
  artifacts: Artifacts.t,
  reach: Reach.t,
  direct: Web.fetch,
  driverPort: int,
  origin: string,
  random: int => Uint8Array.t,
  initialized: unit => bool,
  ready: unit => promise<bool>,
}

let policyOf = Grant_store.policy

let verified = async (t, proof: Access.proof) =>
  switch await Grant_store.get(t.store, proof.grant) {
  | Some(row) if Grant_store.live(t.store, row) =>
    switch Envelope.Hex.decode(row.verifier) {
    | Some(kept) if Access.equal(kept, proof.verifier) =>
      switch policyOf(row) {
      | Ok(Health({control})) =>
        Access.equal(control, await Web.sha256(Web.utf8(t.origin))) ? Some(row) : None
      | Ok(Deploy(_)) => Some(row)
      | Error(_) => None
      }
    | Some(_) | None => None
    }
  | Some(_) | None => None
  }

let caller = async (t, proof) =>
  switch await verified(t, proof) {
  | Some(row) =>
    switch policyOf(row) {
    | Ok(Health(_)) => Access.HealthGrant(proof)
    | Ok(Deploy(_)) => DeploymentGrant(proof)
    | Error(_) => Nobody
    }
  | None => Access.Nobody
  }

let initialized = async (t, d: State.deployment, b: State.binding) =>
  State.ran(d) &&
  d.kind == Some(C.DeploymentKind.Function) &&
  (b.origin != None || (b.address != None && b.bound != None)) &&
  await t.state.hasOrganization(b.organization) &&
  (await t.state.release(d.release))->Option.mapOr(false, r => r.form == C.DeploymentForm.Modules)

let fixed = async (t, row) =>
  switch policyOf(row) {
  | Ok(Deploy(p)) =>
    switch await t.state.deployment(p.app) {
    | Some(d) if d.binding == p.binding && Grant_archive.ingressText(d.ingress) == p.ingress =>
      switch await t.state.binding(d.binding) {
      | Some(b) if b.organization == p.organization => Some((d, b))
      | Some(_) | None => None
      }
    | Some(_) | None => None
    }
  | Ok(Health(_)) | Error(_) => None
  }

let host = (t, b: State.binding): option<Driver.host> =>
  switch (b.origin, b.address) {
  | (Some(origin), _) =>
    Some({
      reach: Reach.direct(origin, t.direct),
      address: "",
      port: t.driverPort,
      token: Access.tokenText(b.id, b.secret),
    })
  | (None, Some(address)) if b.bound != None =>
    Some({reach: t.reach, address, port: t.driverPort, token: Access.tokenText(b.id, b.secret)})
  | (None, Some(_)) | (None, None) => None
  }

let emptyCandidate: C.DeploymentCandidate.t = {
  platform: String.repeat("0", 40),
  cloud: String.repeat("0", 40),
  driver: String.repeat("0", 40),
  machine: String.repeat("0", 40),
}

let described = async (t, app) =>
  switch await Grant_store.head(t.store, app) {
  | Some(h) =>
    switch (
      Envelope.Hex.decode(h.digest),
      C.DeploymentCandidate.fromJson(JSON.parseOrThrow(h.candidate)),
    ) {
    | (Some(digest), Ok(candidate)) =>
      Some(({app, digest, version: h.version, candidate}: C.DeploymentGrantDescribed.t))
    | (None, _) | (Some(_), Error(_)) => None
    }
  | None => None
  }

let stagingKey = (grant, digest) => `staging/${grant}/${digest}`
