/**
 * Every component and every library the drafts name, each component's dependencies as typed edges. An edge
 * says when it is needed and whether its loss is `hard` -- wrong or stopped -- or `soft` -- slower,
 * staler, more garbage, never wrong. A `hard` edge points to its own layer or below; a `soft` one
 * may point up. A target beginning `?` is something the drafts need and no component is yet: a boundary
 * not drawn. Drafts: 13ixj storage, zn3u5 database, 49qyg functions, vuanj components, b8f35 root and
 * backing, wnqvu compat; v7v3w the two halves; 94y0d the foundation and production platforms; the rules
 * they are checked by, `docs/scope.md`. Every `hard`/`soft` here is proposed, not decided; `open_` marks
 * the ones in question.
 */
let vendor = -9

type when_ = [#start | #serve | #deploy | #background]

type half = [#platform | #organization]

type edge = {
  to_: string,
  when_: when_,
  hard: bool,
  why: string,
  /** Why this edge's boundary is not yet clear. */
  open_?: string,
  /**
   * Who defines the format the source reads across this edge, when it is not the target. A format
   * carried unread is no one's to name here: a tablet holding another component's rows reads none of them.
   */
  reads?: string,
  /** Whether this edge is how its component is itself replaced by a new version, D3. */
  replaces?: bool,
}

type component = {
  layer: int,
  /** The ground and the operator are outside the design: trusted as written, never built. */
  kind?: [#ground | #operator],
  /** Whether it keeps state of its own, which must reach the ground to outlast a restart. */
  keeps?: bool,
  /**
   * Whether it is a control, of the platform or of an organization as its half says: an HTTPS API
   * that alone writes configuration, v7v3w. A footing is the same one word, of either, vr5lw.
   */
  control?: bool,
  /** Whether the platform runs it as an owner, in an organization of its own, RFC vuanj. */
  asOwner?: bool,
  /** Which half runs it, RFC v7v3w; the root runs nothing, so it has none. */
  half?: half,
  /**
   * The language its code is written in, RFC fhg6w: ReScript for what must run on a Worker, which
   * runs in `workerd` on a machine alike, and Rust for what runs only natively on one. None where
   * the code is not the platform's: an app is its user's, and the root runs nothing.
   */
  language?: [#rust | #rescript],
  edges: array<edge>,
  uses: array<string>,
}

let e = (to_, when_, hard, why, ~open_=?) => {to_, when_, hard, why, ?open_}
let hard = true
let soft = false
let replaced = {
  ...e("?deployer", #deploy, hard, "replaced by a new version while the rest runs"),
  replaces: true,
}
let key = (~to_="root", ()) =>
  e(to_, #start, hard, "the root public key, deployed, to verify capabilities")

/*
 * Of the components: `console` is a dashboard in an ordinary organization named `console`, holding no
 * privilege, v7v3w; `control(organization)` an organization's control, its products' configuration
 * as an HTTPS API, v7v3w; `control(platform)` the platform's, what spans organizations, as an HTTPS
 * API in no organization, v7v3w; `footing(organization)` and `footing(platform)` what the platform,
 * or the layer beneath, gives a control to stand on, vr5lw.
 */
let components: dict<component> = dict{
  "app": {
    layer: 1,
    half: #organization,
    edges: [
      {
        ...e("compute", #deploy, hard, "an app is deployed as functions, its types checked"),
        replaces: true,
      },
      e("compute", #serve, hard, "it runs as functions"),
      e("storage", #serve, hard, "the buckets it is bound to"),
      e("database", #serve, hard, "the database bound to it"),
      e(
        "control(organization)",
        #deploy,
        hard,
        "opens buckets and databases through its organization's control",
      ),
    ],
    uses: [],
  },
  "console": {
    language: #rescript,
    layer: 1,
    asOwner: true,
    half: #organization,
    edges: [
      {
        ...e("compute", #deploy, hard, "an app like any other, deployed as functions"),
        replaces: true,
      },
      e("compute", #serve, hard, "an app like any other"),
      e(
        "control(platform)",
        #deploy,
        hard,
        "calls the platform's control with its user's credential",
      ),
      e(
        "control(organization)",
        #deploy,
        hard,
        "calls an organization's control with its user's credential",
      ),
    ],
    uses: [],
  },
  "control(organization)": {
    language: #rescript,
    layer: 0,
    control: true,
    half: #organization,
    edges: [
      replaced,
      e(
        "footing(organization)",
        #serve,
        hard,
        "its products' configuration and the bundle it compiles",
      ),
      e(
        "control(platform)",
        #deploy,
        hard,
        "its certificate, allowance and leases, copied down each day and on a change",
      ),
      e(
        "compute",
        #deploy,
        hard,
        "deploys its organization's apps, their types and call graph checked",
      ),
      e(
        "?intermediate",
        #deploy,
        hard,
        "its bundle's signing key, its alone, certified for seven days and renewed each day, v7v3w",
      ),
    ],
    uses: ["capability*", "vocabulary*", "wit*", "extensions*", "placement*", "compat*"],
  },
  "storage": {
    language: #rescript,
    layer: 0,
    half: #organization,
    edges: [
      replaced,
      e("?runner", #serve, hard, "where a tablet's writer and copies are"),
      e(
        "footing(organization)",
        #serve,
        hard,
        "its buckets and their policies, in the bundle, v7v3w",
      ),
      e("tablet", #serve, hard, "its metadata per scope: paths, objects, hashes, references"),
      e("blob", #serve, hard, "content"),
      e("scope", #serve, hard, "a bucket belongs to one"),
      key(),
      e("blob", #background, soft, "sweep: bytes nothing names, hashes nothing counts"),
      e("?clock", #background, soft, "starts the sweep at set times"),
      e(
        "?entry",
        #serve,
        hard,
        "an object bucket answered at a name bound to the storage, public or private",
        ~open_="who checks a private reader is open, 13ixj [C10]",
      ),
    ],
    uses: ["capability*", "compat*"],
  },
  "database": {
    language: #rescript,
    layer: 0,
    half: #organization,
    edges: [
      replaced,
      e("?runner", #serve, hard, "where a tablet's writer and copies are"),
      e(
        "footing(organization)",
        #serve,
        hard,
        "its directory of names and ids, in the bundle, v7v3w",
      ),
      e("tablet", #serve, hard, "a database is a tablet"),
      e("scope", #serve, hard, "ids belong to one"),
      key(),
    ],
    uses: ["capability*", "compat*"],
  },
  "compute": {
    language: #rescript,
    layer: 0,
    half: #organization,
    edges: [
      replaced,
      e("?runner", #serve, hard, "where a tablet's writer and copies are"),
      e("issuer", #serve, hard, "a call's capabilities"),
      e("executor", #serve, hard, "runs the code"),
      e(
        "footing(organization)",
        #serve,
        hard,
        "its apps, versions, declarations, bindings, env, queues and schedules, in the bundle, v7v3w",
      ),
      e(
        "tablet",
        #serve,
        hard,
        "calls and status(id), queues' messages, schedules' repeats, the derive index",
      ),
      e(
        "?builder",
        #deploy,
        hard,
        "code by its hash, fetched from where it was built as its configuration is applied, vr5lw",
      ),
      e("blob", #serve, soft, "derive outputs: a miss runs it again"),
      e("scope", #deploy, hard, "the allowance a declaration must fit"),
      e("?entry", #serve, hard, "a request trigger: HTTP reaches an app's function, 49qyg"),
      e("?entry", #deploy, hard, "binds an app's names, from the bundle, vr5lw"),
      e(
        "database",
        #deploy,
        hard,
        "a deployment opens the migration window",
        ~open_="not in the old graph; whether the call graph also holds bindings is open, 49qyg [C11]",
      ),
      key(),
      e("?clock", #serve, hard, "schedule fires at set times, queue retries wait between tries"),
      e("?clock", #deploy, hard, "writes an app's schedules, in the clock's format"),
    ],
    uses: ["capability*", "vocabulary*", "wit*", "compat*"],
  },
  "scope": {
    language: #rescript,
    layer: -1,
    half: #organization,
    edges: [
      replaced,
      e(
        "footing(organization)",
        #serve,
        hard,
        "its configuration and allowance, in the bundle, v7v3w",
      ),
      e(
        "anchor",
        #deploy,
        hard,
        "its anchor row, compiled into the bundle; it exists by its certificate",
      ),
    ],
    uses: ["compat*"],
  },
  "issuer": {
    language: #rescript,
    layer: -1,
    half: #organization,
    edges: [
      replaced,
      e(
        "footing(organization)",
        #serve,
        hard,
        "reads the scope's grants and allowance in the bundle, in its own format, vuanj",
      ),
      e(
        "?intermediate",
        #deploy,
        hard,
        "its signing key, certified for seven days and renewed each day, the certificate in the bundle and the key a secret deployed beside it, v7v3w",
      ),
    ],
    uses: ["capability*", "vocabulary*", "compat*"],
  },
  "tablet": {
    language: #rescript,
    layer: -1,
    keeps: true,
    half: #organization,
    edges: [
      replaced,
      e("backing", #start, hard, "its copies' stores and what each declares"),
      e("footing(organization)", #serve, hard, "its log, until a snapshot in the blob holds it"),
      e("blob", #background, soft, "archives its log and snapshots"),
      e(
        "blob",
        #start,
        hard,
        "a writer or read copy starts from the last snapshot and the log after it, which the footing keeps until it is archived, at 16 MiB, vuanj",
      ),
      key(),
      e("?runner", #start, hard, "its writer and read copies are placed, and a handover decided"),
    ],
    uses: ["sqlite*", "capability*", "compat*"],
  },
  "blob": {
    language: #rescript,
    layer: -1,
    keeps: true,
    half: #organization,
    edges: [
      replaced,
      e("backing", #serve, hard, "the scope's stores"),
      e("extent", #serve, hard, "which pieces a content is made of, and where each is packed"),
      e("footing(organization)", #serve, hard, "which journal each placement writes"),
      e(
        "vendor",
        #serve,
        hard,
        "parcels and journals written to the scope's stores, at what each store's driver hands back, vr5lw",
      ),
      e(
        "root",
        #start,
        hard,
        "a scope's salt and key, derived from the masters and deployed beside it as secrets, never in the bundle, v7v3w",
      ),
      key(),
      e(
        "extent",
        #background,
        hard,
        "repair after a store is lost: until done, data is held below its placement",
      ),
      e("?clock", #background, soft, "paces a migration the control plane started, b8f35"),
    ],
    uses: ["placement*", "layout*", "keys*", "capability*", "compat*"],
  },
  "executor": {
    language: #rescript,
    layer: -1,
    half: #organization,
    edges: [
      replaced,
      e("host", #serve, hard, "hands each call to the deployment that runs it, vr5lw"),
      e("?roster", #start, hard, "which hosts exist, what each offers"),
      e(
        "?egress",
        #serve,
        hard,
        "an effect's http leaves through the platform's own request interface",
        ~open_="that interface is no component, 49qyg [C14]",
      ),
    ],
    uses: ["vocabulary*", "compat*"],
  },
  "backing": {
    language: #rescript,
    layer: -2,
    keeps: true,
    half: #organization,
    edges: [
      replaced,
      e("anchor", #deploy, hard, "its backing, compiled into the bundle the footing keeps, v7v3w"),
      e("footing(organization)", #serve, hard, "kept in the scope's footing"),
      e(
        "root",
        #start,
        hard,
        "the platform's own stores' secrets; an organization's are deployed beside what reads them, never in its bundle, v7v3w",
      ),
      key(),
    ],
    uses: ["capability*", "compat*"],
  },
  "extent": {
    language: #rescript,
    layer: -2,
    keeps: true,
    half: #organization,
    edges: [
      replaced,
      e("backing", #serve, hard, "a parcel's place from the scope's stores"),
      e("footing(organization)", #serve, hard, "its records, in the scope's footing"),
    ],
    uses: ["placement*", "compat*"],
  },
  "host": {
    language: #rescript,
    layer: -2,
    half: #organization,
    edges: [
      replaced,
      e("machine-driver", #serve, hard, "on a machine, the processes its driver runs, vr5lw"),
      e("cloudflare-driver", #serve, hard, "on Cloudflare, the Workers its driver makes, b8f35"),
    ],
    uses: ["vocabulary*", "compat*"],
  },
  /* A driver of each kind keeps what its vendor gives and nothing of the other's: the two answer the organization's half by one contract the model declares [B30]. */
  "machine-driver": {
    language: #rust,
    layer: -2,
    half: #organization,
    edges: [
      replaced,
      e(
        "vendor",
        #serve,
        hard,
        "a machine's containerd, its firewall and its disk, by their own APIs, vr5lw",
      ),
    ],
    uses: [],
  },
  "cloudflare-driver": {
    language: #rescript,
    layer: -2,
    half: #organization,
    edges: [
      replaced,
      e(
        "vendor",
        #serve,
        hard,
        "an account's Workers, D1 and R2, made and bound through Cloudflare's API, b8f35",
      ),
    ],
    uses: [],
  },
  "anchor": {
    language: #rescript,
    layer: -3,
    keeps: true,
    half: #platform,
    edges: [replaced, e("footing(platform)", #serve, hard, "its rows, in the platform's footing")],
    uses: ["compat*"],
  },
  "control(platform)": {
    language: #rescript,
    layer: -3,
    control: true,
    half: #platform,
    edges: [
      replaced,
      e(
        "footing(platform)",
        #serve,
        hard,
        "configuration spanning organizations, in the platform's footing",
      ),
      e("anchor", #serve, hard, "opens, suspends and deletes organizations by their rows"),
      e("root", #start, hard, "the masters, to derive each organization's salt and key"),
      e("?intermediate", #deploy, hard, "certifies each organization's key"),
    ],
    uses: ["capability*", "keys*", "extensions*", "compat*"],
  },
  "root": {
    layer: -4,
    edges: [
      {...e("?source", #deploy, hard, "what it holds reaches each component"), replaces: true},
    ],
    uses: [],
  },
  "footing(organization)": {layer: vendor, kind: #ground, half: #organization, edges: [], uses: []},
  "footing(platform)": {layer: vendor, kind: #ground, half: #platform, edges: [], uses: []},
  "vendor": {layer: vendor, kind: #ground, edges: [], uses: []},
  "operator": {layer: vendor, kind: #operator, edges: [], uses: []},
}

let globalOpen: array<string> = []
