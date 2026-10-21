/**
 * What each driver is made of, RFC vr5lw: one implementation for each kind its vendor's resources
 * give, `model/ground/resources.res`. A kind is a contract the model declares,
 * `model/contracts/kinds/`, with no language of its own; each implementation of it has one, since a
 * Worker over R2 and a process over a machine's file system do the same work on grounds that share
 * nothing. Nothing calls an implementation but through its kind's contract, and no implementation
 * calls another.
 */
type implementation = {
  kind: Resources.kind,
  language: [#rust | #rescript],
  as_: string,
  /** The platform's libraries it may depend on, by the model's names. */
  uses?: array<string>,
  /** What of others' it may take, `model/graph/libraries.res`. */
  takes?: array<Libraries.taken>,
}

/**
 * A runtime a driver gives compute by, RFC vr5lw: the form it takes and every isolation it stands
 * on, each a choice of `model/contracts/kinds/deployments.res`. An isolate run in a container
 * stands on both, so isolation is a list, and a kind added later, a virtual machine's, one more.
 */
type runtime = {name: string, takes: string, stands: array<string>}

/**
 * A driver is its implementations and its management, `management/` beside them: the process that
 * answers the management interface and hands each call to the implementation of its kind, in the
 * language the driver's ground asks, vr5lw. A driver whose ground is a machine holds its system as
 * well, `system/`: what the machine runs beneath it, a NixOS module in Nix, its disk, and the template
 * a machine's own flake starts from, which the root's `flake.nix` gives, vr5lw.
 */
type driver = {
  grounds: array<Steps.ground>,
  management: [#rust | #rescript],
  implements: array<implementation>,
  runtimes: array<runtime>,
  system?: string,
  /** The images it runs its isolate runtimes from, each a program in a container, built by Docker. */
  images?: string,
}

let drivers: dict<driver> = dict{
  "driver(cloudflare)": {
    grounds: [#cloudflare],
    management: #rescript,
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
  "driver(machine)": {
    grounds: [#provider, #home],
    management: #rust,
    system: "NixOS, with containerd",
    images: "workerd and wasmtime",
    implements: [
      {kind: #function, language: #rust, as_: "workerd, run for each deployment"},
      {kind: #instance, language: #rust, as_: "a process"},
      {
        kind: #container,
        language: #rust,
        as_: "a container, by containerd",
        uses: ["envelope*"],
        takes: [
          {language: #rust, name: "containerd-client", major: "0.9"},
          {language: #rust, name: "tokio", major: "1"},
          {language: #rust, name: "serde_json", major: "1"},
          {language: #rust, name: "sha2", major: "0.10"},
        ],
      },
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
