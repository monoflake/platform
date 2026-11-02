/** The two grant policies reviewed in grant-review.md, separate from identity and certificates. */
open Subset

let types: array<declared> = [
  {
    name: "deployment-grant-mint",
    def: Record([field("policy", 1, Type("deployment-grant-mint-policy"))]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-mint-policy",
    def: Union({
      tag: "policy",
      cases: [
        {
          name: "deploy",
          code: 1,
          fields: [field("app", 1, Id("app")), field("expires", 2, Prim(#uint53))],
        },
        {name: "health", code: 2, fields: [field("expires", 2, Prim(#uint53))]},
      ],
    }),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-id",
    def: Record([field("grant", 1, Prim(#string))]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-minted",
    def: Record([
      field("grant", 1, Prim(#string)),
      field("bearer", 2, Prim(#secret)),
      field("expires", 3, Prim(#uint53)),
    ]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-policy",
    def: Union({
      tag: "policy",
      cases: [
        {
          name: "deploy",
          code: 1,
          fields: [
            field("app", 1, Id("app")),
            field("organization", 2, Prim(#uint32)),
            field("binding", 3, Prim(#uint32)),
            field("ingress", 4, Prim(#string)),
          ],
        },
        {name: "health", code: 2, fields: [field("control", 1, Prim(#hash))]},
      ],
    }),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-verifier",
    def: Record([
      field("grant", 1, Prim(#string)),
      field("verifier", 2, Prim(#hash)),
      field("expires", 3, Prim(#uint53)),
      field("revoked", 4, Prim(#bool)),
      field("policy", 5, Type("deployment-grant-policy")),
    ]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-upload",
    def: Record([field("artifact", 1, Prim(#bytes)), field("digest", 2, Prim(#hash))]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-artifact",
    def: Record([field("digest", 1, Prim(#hash)), field("expires", 2, Prim(#uint53))]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-candidate",
    def: Record([
      field("platform", 1, Prim(#string)),
      field("cloud", 2, Prim(#string)),
      field("driver", 3, Prim(#string)),
      field("machine", 4, Prim(#string)),
    ]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-staging",
    def: Record([
      field("grant", 1, Prim(#string)),
      field("digest", 2, Prim(#hash)),
      field("size", 3, Prim(#uint53)),
      field("expires", 4, Prim(#uint53)),
    ]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-audit",
    def: Record([
      field("grant", 1, Prim(#string)),
      field("digest", 2, Prim(#hash)),
      field("previous", 3, Prim(#uint53)),
      field("version", 4, Prim(#uint53)),
      field("candidate", 5, Type("deployment-candidate")),
    ]),
    from: "control-deploy-grant",
  },
  {
    name: "deployment-grant-deploy",
    def: Record([
      field("digest", 1, Prim(#hash)),
      field("expected", 2, Prim(#uint53)),
      field("candidate", 3, Type("deployment-candidate")),
    ]),
    from: "control-deploy-grant",
  },
  {name: "deployment-grant-status", def: Record([]), from: "control-deploy-grant"},
  {
    name: "deployment-grant-described",
    def: Record([
      field("app", 1, Id("app")),
      field("digest", 2, Prim(#hash)),
      field("version", 3, Prim(#uint53)),
      field("candidate", 4, Type("deployment-candidate")),
    ]),
    from: "control-deploy-grant",
  },
]

let mintLifetimeDays = 180

let interface_: interface_ = {
  name: "deployment_grants",
  version: 2,
  from: "control-deploy-grant",
  bounds: dict{"artifact": 33554432, "staging_ms": 3600000, "lifetime_days": mintLifetimeDays},
  operations: [
    op(
      "mint",
      "deployment-grant-mint",
      "deployment-grant-minted",
      [("invalid", #rejected), ("not_found", #rejected), ("unbound", #rejected)],
      ~callers=[#operator],
    ),
    op(
      "revoke",
      "deployment-grant-id",
      "deployment-grant-id",
      [("not_found", #rejected)],
      ~callers=[#operator],
    ),
    op(
      "upload",
      "deployment-grant-upload",
      "deployment-grant-artifact",
      [("invalid", #rejected), ("too_large", #rejected), ("hash_mismatch", #rejected)],
      ~callers=[#deployment_grant],
    ),
    op(
      "deploy",
      "deployment-grant-deploy",
      "deployment-grant-described",
      [
        ("not_found", #rejected),
        ("invalid", #rejected),
        ("stale", #rejected),
        ("unbound", #rejected),
        ("unreachable", #unavailable),
        ("bad_answer", #unavailable),
      ],
      ~callers=[#deployment_grant],
    ),
    op(
      "status",
      "deployment-grant-status",
      "deployment-grant-described",
      [],
      ~callers=[#deployment_grant],
    ),
    Health_grants.operation,
  ],
}
