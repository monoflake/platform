/**
 * What each driver is made of, RFC vr5lw: one implementation for each kind its vendor's resources
 * give, `model/ground/resources.res`. A kind is a contract the model declares [B30], with no
 * language of its own; each implementation of it has one, since a Worker over R2 and a process over
 * a machine's file system do the same work on grounds that share nothing. Nothing calls an
 * implementation but through its kind's contract, and no implementation calls another.
 */
type implementation = {kind: Resources.kind, language: [#rust | #rescript], as_: string}

type driver = {grounds: array<Steps.ground>, implements: array<implementation>}

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
  },
}
