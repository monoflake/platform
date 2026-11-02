/** The health policy binds the receiving control and this operation alone. */
open Subset

let types: array<declared> = [
  {
    name: "health-request",
    def: Record([field("nonce", 1, Prim(#hash))]),
    from: "control-deploy-grant",
  },
  {
    name: "health-state",
    def: Enum({choices: codes(["ready", "unavailable"]), ordered: false}),
    from: "control-deploy-grant",
  },
  {
    name: "health-answer",
    def: Record([field("nonce", 1, Prim(#hash)), field("state", 2, Type("health-state"))]),
    from: "control-deploy-grant",
  },
]

let operation = op("health", "health-request", "health-answer", [], ~callers=[#health_grant])
