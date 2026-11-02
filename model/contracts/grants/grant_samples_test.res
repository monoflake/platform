/** The model-local grant cases use the shared conformance checker before the policy simulation. */
open Testing

let member = (j, name) => j->JSON.Decode.object->Option.flatMap(d => d->Dict.get(name))
let text = (j, name) => member(j, name)->Option.flatMap(JSON.Decode.string)
let items = (j, name) => member(j, name)->Option.flatMap(JSON.Decode.array)->Option.getOr([])
let number = (j, name, default) =>
  member(j, name)->Option.flatMap(JSON.Decode.float)->Option.getOr(default)
let flag = (j, name, default) =>
  member(j, name)->Option.flatMap(JSON.Decode.bool)->Option.getOr(default)

let state = (j): Grant_policy.state => {
  let d = Grant_policy.defaults
  {
    now: number(j, "now", d.now),
    commit: number(j, "commit", d.commit),
    expires: number(j, "expires", d.expires),
    revoked: flag(j, "revoked", d.revoked),
    revokedAtCommit: flag(j, "revokedAtCommit", d.revokedAtCommit),
    appExists: flag(j, "appExists", d.appExists),
    initialized: flag(j, "initialized", d.initialized),
    policyMatches: flag(j, "policyMatches", d.policyMatches),
    modules: flag(j, "modules", d.modules),
    archiveValid: flag(j, "archiveValid", d.archiveValid),
    digestMatches: flag(j, "digestMatches", d.digestMatches),
    size: number(j, "size", Int.toFloat(d.size))->Int.fromFloat,
    artifactOwned: flag(j, "artifactOwned", d.artifactOwned),
    artifactExpires: number(j, "artifactExpires", d.artifactExpires),
    expectedMatches: flag(j, "expectedMatches", d.expectedMatches),
    serialized: flag(j, "serialized", d.serialized),
    candidateValid: flag(j, "candidateValid", d.candidateValid),
    reachable: flag(j, "reachable", d.reachable),
    grantExists: flag(j, "grantExists", d.grantExists),
    healthMint: false,
    controlMatches: flag(j, "controlMatches", d.controlMatches),
    verifierMatches: flag(j, "verifierMatches", d.verifierMatches),
    storeReadable: flag(j, "storeReadable", d.storeReadable),
  }
}

let proof = (step): Subset.caller =>
  switch text(step, "as") {
  | Some("operator") => #operator
  | Some("deployment_grant") => #deployment_grant
  | Some("health_grant") => #health_grant
  | Some("organization") => #organization
  | Some("host") => #host
  | _ => JsError.throwWithMessage("a grant case must name its proof kind")
  }

let scope = (): Conforms.scope => {
  found: [],
  captured: Set.make(),
  bounds: Deployment_grants.interface_.bounds->Option.getOr(dict{}),
  declared: [],
  fixtures: [],
}

let covered = Set.make()
let denied = Set.make()
let sampled = Set.make()
let paths = Cases.files("model/contracts/grants/samples")
paths->Array.forEach(path => {
  let suite = Cases.read(path)
  let name = text(suite, "interface")->Option.getOrThrow
  let interface = Contracts.interfaces->Array.find(i => i.name == name)->Option.getOrThrow
  items(suite, "cases")->Array.forEach(c => {
    let description = text(c, "description")->Option.getOrThrow
    test(
      description,
      () => {
        let observations = member(c, "given")->Option.getOr(JSON.Object(dict{}))
        let s = state(observations)
        let steps = items(c, "steps")
        deepEqual(steps == [], false)
        steps->Array.forEach(
          step => {
            let call = text(step, "call")->Option.getOrThrow
            let operation = interface.operations->Array.find(o => o.name == call)->Option.getOrThrow
            let input = member(step, "input")->Option.getOrThrow
            let expect = member(step, "expect")->Option.getOrThrow
            let check = scope()
            Conforms.conforms(check, Type(operation.input), input, Input, description)
            let reason = if check.found != [] {
              Some("malformed")
            } else {
              let s = if name == "deployment_grants" && call == "mint" {
                let policy = member(input, "policy")->Option.getOrThrow
                {
                  ...s,
                  expires: number(policy, "expires", 0.),
                  healthMint: text(policy, "policy") == Some("health"),
                }
              } else {
                s
              }
              Grant_policy.decide(~interface=name, ~operation, ~proof=proof(step), s)
            }
            deepEqual(reason, text(expect, "reason"), ~message=description)
            switch reason {
            | None =>
              let out = member(expect, "output")->Option.getOrThrow
              Conforms.conforms(check, Type(operation.output), out, Expected, description)
              deepEqual(check.found, [])
              if name == "deployment_grants" && call == "health" {
                deepEqual(
                  out,
                  Grant_policy.healthAnswer(s, member(input, "nonce")->Option.getOrThrow),
                )
              }
            | Some(reason) =>
              let reasons = Array.concat(operation.reasons, Calls.common)
              let declared = reasons->Array.find(r => r.name == reason)->Option.getOrThrow
              deepEqual(text(expect, "failure"), Some((declared.failure :> string)))
              sampled->Set.add(`${name}.${call}.${reason}`)
              if reason == "denied" {
                denied->Set.add(`${(proof(step) :> string)}.${name}.${call}`)
              }
            }
            covered->Set.add(`${name}.${call}`)
          },
        )
      },
    )
  })
})

test("grant samples cover all operations and declared reasons", () => {
  Deployment_grants.interface_.operations->Array.forEach(o => {
    deepEqual(covered->Set.has(`deployment_grants.${o.name}`), true)
    if o.callers->Array.includes(#deployment_grant) {
      deepEqual(denied->Set.has(`health_grant.deployment_grants.${o.name}`), true)
    }
    if o.callers->Array.includes(#health_grant) {
      deepEqual(o.callers, [#health_grant])
      deepEqual(denied->Set.has(`deployment_grant.deployment_grants.${o.name}`), true)
    }
    o.reasons->Array.forEach(
      r => deepEqual(sampled->Set.has(`deployment_grants.${o.name}.${r.name}`), true),
    )
  })
})

test("every existing operator operation has a grant denial", () => {
  Contracts.interfaces->Array.forEach(i => {
    i.operations->Array.forEach(
      o => {
        if o.callers->Array.includes(#operator) {
          let grants: array<Subset.caller> = [#deployment_grant, #health_grant]
          grants->Array.forEach(
            p =>
              deepEqual(
                denied->Set.has(`${(p :> string)}.${i.name}.${o.name}`),
                true,
                ~message=`${(p :> string)}.${i.name}.${o.name}`,
              ),
          )
        }
      },
    )
  })
})

test("a grant is neither an account credential nor a certificate role", () => {
  deepEqual(Contracts.members("certificate-role")->Array.includes("deployment_grant"), false)
  deepEqual(Contracts.members("certificate-role")->Array.includes("health_grant"), false)
  deepEqual(Grant_policy.secretBytes, 32)
  deepEqual(Grant_policy.network, ["http"])
  deepEqual(Grant_policy.form, "modules")
  deepEqual(Grant_policy.bearerPrefix, "dg1.")
  deepEqual(Grant_policy.verifier, "sha256")
})
