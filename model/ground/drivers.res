/**
 * What this model asks of each driver role and nothing of how one is built, RFC 7ykg6. The
 * drivers' own model fills them, `model/graph/fill.res`, and nothing calls one but through a kind.
 */
/** A kind a driver gives, by the contract reaching it at its version, a volume by none. */
type kind = {kind: Resources.kind, contract?: string, version?: int}

/**
 * A runtime a driver gives compute by, the form it takes and every isolation it stands on, RFC
 * vr5lw.
 */
type runtime = {name: string, takes: string, stands: array<string>}

/** A driver role as this model asks it and as a fill gives it, the one shape for both. */
type driver = {
  grounds: array<Steps.ground>,
  kinds: array<kind>,
  /** The version of `management` its management answers. */
  management: int,
  runtimes: array<runtime>,
}

/** The version this model declares of a contract, none where it declares no such contract. */
let versionOf = contract =>
  Contracts.interfaces->Array.find(i => i.name == contract)->Option.map(i => i.version)

/** A kind asked at its contract's version as this model declares it now. */
let at = (kind: Resources.kind): kind =>
  switch kind {
  | #function | #instance | #container => {
      kind,
      contract: "deployments",
      version: ?versionOf("deployments"),
    }
  | #object => {kind, contract: "object", version: ?versionOf("object")}
  | #database => {kind, contract: "database", version: ?versionOf("database")}
  | #volume => {kind: kind}
  }

let management = versionOf("management")->Option.getOr(0)

/** Each driver role, by the name the graph gives it, `model/graph/components.res`. */
let asked: dict<driver> = dict{
  "driver(cloudflare)": {
    grounds: [#cloudflare],
    kinds: [#function, #instance, #object, #database]->Array.map(at),
    management,
    runtimes: [{name: "workers", takes: "modules", stands: ["isolate"]}],
  },
  "driver(machine)": {
    grounds: [#provider, #home],
    kinds: [#function, #instance, #container, #object, #volume, #database]->Array.map(at),
    management,
    // An isolate runs inside its organization's container, which keeps bindings apart, v7v3w.
    runtimes: [
      {name: "workerd", takes: "modules", stands: ["isolate", "kernel"]},
      {name: "wasmtime", takes: "component", stands: ["isolate", "kernel"]},
      {name: "runc", takes: "image", stands: ["kernel"]},
      {name: "crun", takes: "image", stands: ["kernel"]},
      {name: "youki", takes: "image", stands: ["kernel"]},
    ],
  },
}

/** What a fill gives of the driver roles, none when this model is checked alone. */
let given: option<dict<driver>> = Fill.part(Fill.drivers)
