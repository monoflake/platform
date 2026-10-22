/**
 * What each driver is made of, one implementation for each kind its vendor gives,
 * `model/ground/resources.res`, RFC vr5lw. Nothing calls one but through its kind's contract.
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
 * A runtime a driver gives compute by, the form it takes and every isolation it stands on, RFC
 * vr5lw.
 */
type runtime = {name: string, takes: string, stands: array<string>}

/**
 * A driver is its implementations and its `management/`, vr5lw; a machine's NixOS is
 * `monoflake/machine`'s and its isolate runtimes' images `monoflake/runtime`'s, RFC m7rkq.
 */
type driver = {
  grounds: array<Steps.ground>,
  management: [#rust | #rescript],
  /** What of others' its management may take, `model/graph/libraries.res`. */
  managementTakes?: array<Libraries.taken>,
  implements: array<implementation>,
  runtimes: array<runtime>,
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
    managementTakes: [
      {language: #rust, name: "rustix", major: "1"},
      {language: #rust, name: "blake3", major: "1"},
    ],
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
          {language: #rust, name: "sha2", major: "0.11"},
          {language: #rust, name: "prost-types", major: "0.14"},
          {language: #rust, name: "tonic", major: "0.14"},
          {language: #rust, name: "reqwest", major: "0.13"},
          {language: #rust, name: "chacha20poly1305", major: "0.11"},
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
