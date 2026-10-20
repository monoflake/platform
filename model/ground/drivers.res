/**
 * What each driver is made of, RFC vr5lw: one implementation for each kind its vendor's resources
 * give, `model/ground/resources.res`. A kind is a contract the model declares [B30], with no
 * language of its own; each implementation of it has one, since a Worker over R2 and a process over
 * a machine's file system do the same work on grounds that share nothing. Nothing calls an
 * implementation but through its kind's contract, and no implementation calls another.
 */
type implementation = {kind: Resources.kind, language: [#rust | #rescript], as_: string}

/**
 * A runtime a driver gives compute by, RFC vr5lw: the form it takes and every isolation it stands
 * on, each a choice of `model/contracts/kinds/deployments.res`. An isolate run in a container
 * stands on both, so isolation is a list, and a kind added later, a virtual machine's, one more.
 */
type runtime = {name: string, takes: string, stands: array<string>}

type driver = {
  grounds: array<Steps.ground>,
  implements: array<implementation>,
  runtimes: array<runtime>,
}

let drivers: dict<driver> = dict{
  "cloudflare-driver": {
    grounds: [#cloudflare],
    implements: [
      {
        kind: #function,
        language: #rescript,
        as_: "a Worker of each deployment, made through Cloudflare's API",
      },
      {kind: #instance, language: #rescript, as_: "a Durable Object"},
      {kind: #object, language: #rescript, as_: "a Worker over R2"},
      {kind: #database, language: #rescript, as_: "a Worker over D1, or a Durable Object's SQLite"},
    ],
    runtimes: [{name: "workers", takes: "modules", stands: ["isolate"]}],
  },
  "machine-driver": {
    grounds: [#provider, #home],
    implements: [
      {kind: #function, language: #rust, as_: "workerd, run for each deployment"},
      {kind: #instance, language: #rust, as_: "a process"},
      {kind: #container, language: #rust, as_: "a container, by containerd"},
      {kind: #object, language: #rust, as_: "objects on the machine's file system"},
      {kind: #volume, language: #rust, as_: "a btrfs subvolume"},
      {kind: #database, language: #rust, as_: "SQLite on a volume"},
    ],
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
