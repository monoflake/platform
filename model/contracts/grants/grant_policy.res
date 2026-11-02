/** A policy simulation for the contract, with request and commit observations kept apart. */
type state = {
  now: float,
  commit: float,
  expires: float,
  revoked: bool,
  revokedAtCommit: bool,
  appExists: bool,
  initialized: bool,
  policyMatches: bool,
  modules: bool,
  archiveValid: bool,
  digestMatches: bool,
  size: int,
  artifactOwned: bool,
  artifactExpires: float,
  expectedMatches: bool,
  serialized: bool,
  candidateValid: bool,
  reachable: bool,
  grantExists: bool,
  healthMint: bool,
  controlMatches: bool,
  verifierMatches: bool,
  storeReadable: bool,
}

let defaults = {
  now: 1000.,
  commit: 1000.,
  expires: 2000.,
  revoked: false,
  revokedAtCommit: false,
  appExists: true,
  initialized: true,
  policyMatches: true,
  modules: true,
  archiveValid: true,
  digestMatches: true,
  size: 1,
  artifactOwned: true,
  artifactExpires: 2000.,
  expectedMatches: true,
  serialized: true,
  candidateValid: true,
  reachable: true,
  grantExists: true,
  healthMint: false,
  controlMatches: true,
  verifierMatches: true,
  storeReadable: true,
}

let artifactBound = 33554432
let stagingMs = 3600000.
let bearerPrefix = "dg1."
let secretBytes = 32
let verifier = "sha256"
let form = "modules"
let network = ["http"]
let mintLifetimeMs = Deployment_grants.mintLifetimeDays->Int.toFloat *. 86400000.

/** Times are Unix milliseconds, finite safe integers, with no unbounded expiry. */
let future = (~now, expires) =>
  Math.floor(expires) == expires && expires > now && expires <= 9007199254740991.

let live = (s, ~at, ~revoked) =>
  s.grantExists && s.verifierMatches && !revoked && future(~now=at, s.expires)

let healthAnswer = (s, nonce) => JSON.Object(
  dict{
    "nonce": nonce,
    "state": String(s.initialized && s.storeReadable ? "ready" : "unavailable"),
  },
)

/** None permits the operation; a reason refuses before any effect. */
let decide = (~interface, ~operation: Subset.operation, ~proof: Subset.caller, s) => {
  if !(operation.callers->Array.includes(proof)) {
    Some("denied")
  } else if interface != Deployment_grants.interface_.name {
    None
  } else {
    switch operation.name {
    | "mint" =>
      if !future(~now=s.now, s.expires) || s.expires > s.now +. mintLifetimeMs {
        Some("invalid")
      } else if s.healthMint {
        None
      } else if !s.appExists {
        Some("not_found")
      } else if !s.initialized {
        Some("unbound")
      } else {
        None
      }
    | "revoke" => s.grantExists ? None : Some("not_found")
    | "health" =>
      if !live(s, ~at=s.now, ~revoked=s.revoked) || !s.controlMatches || !s.policyMatches {
        Some("denied")
      } else {
        None
      }
    | "upload" | "deploy" | "status" =>
      if !live(s, ~at=s.now, ~revoked=s.revoked) {
        Some("denied")
      } else if !s.policyMatches || !s.appExists {
        Some("denied")
      } else if operation.name == "status" {
        None
      } else if !live(s, ~at=s.commit, ~revoked=s.revoked || s.revokedAtCommit) {
        Some("denied")
      } else if !s.modules || !s.archiveValid {
        Some("invalid")
      } else if operation.name == "upload" {
        if s.size > artifactBound {
          Some("too_large")
        } else if !s.digestMatches {
          Some("hash_mismatch")
        } else {
          None
        }
      } else if !s.initialized {
        Some("unbound")
      } else if !s.artifactOwned || s.artifactExpires <= s.commit {
        Some("not_found")
      } else if !s.candidateValid {
        Some("invalid")
      } else if !s.digestMatches {
        Some("invalid")
      } else if !s.expectedMatches || !s.serialized {
        Some("stale")
      } else if !s.reachable {
        Some("unreachable")
      } else {
        None
      }
    | _ => Some("denied")
    }
  }
}
