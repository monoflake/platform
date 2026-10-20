/**
 * Every component and every library the drafts name, each component's dependencies as typed edges.
 * An edge says when it is needed and whether its loss is `hard` -- wrong or stopped -- or `soft` --
 * slower, staler, more garbage, never wrong. A `hard` edge points to its own layer or below; a
 * `soft` one may point up. A target beginning `?` is something the drafts need and no component is
 * yet: a boundary not drawn. Drafts: 13ixj storage, zn3u5 database, 49qyg functions, vuanj
 * components, b8f35 root and backing, wnqvu compat; v7v3w the two halves; 94y0d the foundation and
 * production platforms; the rules they are checked by, `docs/scope.md`. Every `hard`/`soft` here is
 * proposed, not decided; `open_` marks the ones in question.
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
   * carried unread is no one's to name here: a tablet holding another component's rows reads none
   * of them.
   */
  reads?: string,
  /** Whether this edge is how its component is itself replaced by a new version, D3. */
  replaces?: bool,
  /**
   * What crosses this edge between two processes, RFC fhg6w: an interface of `model/contracts/`, a
   * signed record, a bundle's section as `bundle.{section}`, a record kind of the footing as
   * `record.{kind}`, or `records`, every kind the source writes there; `wit`, an app's own exports;
   * or `?{name}`, a contract not yet declared, `undeclared` below.
   */
  contract?: array<string>,
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

let e = (to_, when_, hard, why, ~open_=?, ~contract=?) => {to_, when_, hard, why, ?open_, ?contract}
let hard = true
let soft = false
let replaced = {
  ...e("?deployer", #deploy, hard, "replaced by a new version while the rest runs"),
  replaces: true,
}
let key = (~to_="root", ()) =>
  e(
    to_,
    #start,
    hard,
    "the root public key, deployed, to verify capabilities",
    ~contract=["certificate"],
  )

/*
 * Of the components: `console` is a dashboard in an ordinary organization named `console`, holding
 * no privilege, v7v3w; `control(organization)` an organization's control, its products'
 * configuration as an HTTPS API, v7v3w; `control(platform)` the platform's, what spans
 * organizations, as an HTTPS API in no organization, v7v3w; `footing(organization)` and
 * `footing(platform)` what the platform, or the layer beneath, gives a control to stand on, vr5lw.
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
      e("compute", #serve, hard, "it runs as functions", ~contract=["wit"]),
      e("storage", #serve, hard, "the buckets it is bound to", ~contract=["?storage"]),
      e("database", #serve, hard, "the database bound to it", ~contract=["database"]),
      e(
        "control(organization)",
        #deploy,
        hard,
        "opens buckets and databases through its organization's control",
        ~contract=["?control(organization)"],
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
      e("compute", #serve, hard, "an app like any other", ~contract=["wit"]),
      e(
        "control(platform)",
        #deploy,
        hard,
        "calls the platform's control with its user's credential",
        ~contract=["?control(platform)"],
      ),
      e(
        "control(organization)",
        #deploy,
        hard,
        "calls an organization's control with its user's credential",
        ~contract=["?control(organization)"],
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
        ~contract=["records", "bundle"],
      ),
      e(
        "control(platform)",
        #deploy,
        hard,
        "its certificate, allowance and loans, copied down each day and on a change",
        ~contract=["?control(platform)"],
      ),
      e(
        "compute",
        #deploy,
        hard,
        "deploys its organization's apps, their types and call graph checked",
        ~contract=["?compute"],
      ),
      e(
        "?intermediate",
        #deploy,
        hard,
        "its bundle's signing key, its alone, certified for seven days and renewed each day, v7v3w",
      ),
      e(
        "driver(machine)",
        #deploy,
        hard,
        "applies the capacity it opens on each machine extension, vr5lw",
        ~contract=["management"],
      ),
      e(
        "driver(cloudflare)",
        #deploy,
        hard,
        "applies the capacity it opens on each Cloudflare extension, vr5lw",
        ~contract=["management"],
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
        ~contract=["bundle.storage"],
      ),
      e(
        "tablet",
        #serve,
        hard,
        "its metadata per scope: paths, objects, hashes, references",
        ~contract=["database"],
      ),
      e("blob", #serve, hard, "content", ~contract=["?blob"]),
      e("scope", #serve, hard, "a bucket belongs to one", ~contract=["?scope"]),
      key(),
      e(
        "blob",
        #background,
        soft,
        "sweep: bytes nothing names, hashes nothing counts",
        ~contract=["?blob"],
      ),
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
        ~contract=["bundle.database"],
      ),
      e("tablet", #serve, hard, "a database is a tablet", ~contract=["database"]),
      e("scope", #serve, hard, "ids belong to one", ~contract=["?scope"]),
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
      e("issuer", #serve, hard, "a call's capabilities", ~contract=["?issuer"]),
      e("executor", #serve, hard, "runs the code", ~contract=["?executor"]),
      e(
        "footing(organization)",
        #serve,
        hard,
        "its apps, versions, declarations, bindings, env, queues and schedules, in the bundle, v7v3w",
        ~contract=["bundle.compute"],
      ),
      e(
        "tablet",
        #serve,
        hard,
        "calls and status(id), queues' messages, schedules' repeats, the derive index",
        ~contract=["database"],
      ),
      e(
        "?builder",
        #deploy,
        hard,
        "code by its hash, fetched from where it was built as its configuration is applied, vr5lw",
      ),
      e("blob", #serve, soft, "derive outputs: a miss runs it again", ~contract=["?blob"]),
      e("scope", #deploy, hard, "the allowance a declaration must fit", ~contract=["?scope"]),
      e("?entry", #serve, hard, "a request trigger: HTTP reaches an app's function, 49qyg"),
      e("?entry", #deploy, hard, "binds an app's names, from the bundle, vr5lw"),
      e(
        "database",
        #deploy,
        hard,
        "a deployment opens the migration window",
        ~contract=["?migration"],
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
        ~contract=["bundle.issuer"],
      ),
      e(
        "anchor",
        #deploy,
        hard,
        "its anchor row, which names where its backing is kept; it exists by its certificate",
        ~contract=["?anchor"],
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
        ~contract=["bundle.issuer"],
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
      e(
        "backing",
        #start,
        hard,
        "its copies' stores and what each declares",
        ~contract=["?backing"],
      ),
      e(
        "footing(organization)",
        #start,
        hard,
        "which copies hold a tablet on machines, its primary and generation, raised only as one is taken over, vuanj",
        ~contract=["record.writer"],
      ),
      e(
        "blob",
        #background,
        soft,
        "archives a machine copy's WAL and its snapshots, vuanj",
        ~contract=["?blob"],
      ),
      e(
        "blob",
        #start,
        hard,
        "a copy added starts from its volume's last snapshot, then takes what is after from its primary, vuanj",
        ~contract=["?blob"],
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
      e("backing", #serve, hard, "the scope's stores", ~contract=["?backing"]),
      e(
        "extent",
        #serve,
        hard,
        "which pieces a content is made of, and where each is packed",
        ~contract=["?extent"],
      ),
      e(
        "footing(organization)",
        #serve,
        hard,
        "which journal each placement writes",
        ~contract=["record.journal"],
      ),
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
        ~contract=["deployments"],
      ),
      key(),
      e(
        "extent",
        #background,
        hard,
        "repair after a store is lost: until done, data is held below its placement",
        ~contract=["?extent"],
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
      e(
        "host",
        #serve,
        hard,
        "hands each call to the deployment that runs it, vr5lw",
        ~contract=["wit"],
      ),
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
      e(
        "anchor",
        #deploy,
        hard,
        "its scope's row, which names where its backing is kept, b8f35",
        ~contract=["?anchor"],
      ),
      e(
        "footing(organization)",
        #serve,
        hard,
        "kept in the scope's footing",
        ~contract=["record.store"],
      ),
      e(
        "root",
        #start,
        hard,
        "the platform's own stores' secrets; an organization's are deployed beside what reads them, never in its bundle, v7v3w",
        ~contract=["deployments"],
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
      e(
        "backing",
        #serve,
        hard,
        "a parcel's place from the scope's stores",
        ~contract=["?backing"],
      ),
      e(
        "footing(organization)",
        #serve,
        hard,
        "its records, in the scope's footing",
        ~contract=["record.content", "record.piece", "record.parcel"],
      ),
    ],
    uses: ["placement*", "compat*"],
  },
  "host": {
    language: #rescript,
    layer: -2,
    half: #organization,
    edges: [
      replaced,
      e(
        "driver(machine)",
        #serve,
        hard,
        "on a machine, the processes its driver runs, vr5lw",
        ~contract=["deployments"],
      ),
      e(
        "driver(cloudflare)",
        #serve,
        hard,
        "on Cloudflare, the Workers its driver makes, b8f35",
        ~contract=["deployments"],
      ),
    ],
    uses: ["vocabulary*", "compat*"],
  },
  /*
   * A driver is made of implementations, one for each kind its vendor gives, each in its own
   * language, `model/ground/drivers.res`.
   */
  "driver(machine)": {
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
  "driver(cloudflare)": {
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
    edges: [
      replaced,
      e(
        "footing(platform)",
        #serve,
        hard,
        "its rows, in the platform's footing",
        ~contract=["?anchor"],
      ),
    ],
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
        ~contract=["records", "bundle"],
      ),
      e(
        "anchor",
        #serve,
        hard,
        "opens, suspends and deletes organizations by their rows",
        ~contract=["?anchor"],
      ),
      e(
        "root",
        #start,
        hard,
        "the masters, to derive each organization's salt and key",
        ~contract=["deployments"],
      ),
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

/** The platform's control plane, licensed AGPL-3.0-only; every other component and every library
 * is MIT OR Apache-2.0, RFC fhg6w. */
let agpl = ["control(platform)", "control(organization)", "anchor", "console"]

let permissive = "MIT OR Apache-2.0"

/** The license a component's code is under, as its manifests declare it. */
let licenseOf = name => agpl->Array.includes(name) ? "AGPL-3.0-only" : permissive

/**
 * The contracts an edge names that are not yet declared in the subset, by the name it gives each
 * after `?`, and the row that declares them. A tablet's copies speak among themselves -- WAL frames
 * from a primary, a generation taken by a majority, vuanj -- on no edge, as they are one component.
 */
let undeclared: array<(string, string)> = [
  (
    "storage",
    "the storage product's interface, an app's: buckets, files and objects, and publish, vr5lw [B32]",
  ),
  ("compute", "the compute product's deployment of an app, its types and call graph checked [B32]"),
  ("migration", "a database's migration window, which a deployment opens, zn3u5 [B32]"),
  ("control(organization)", "an organization's control's configuration API, v7v3w [B32]"),
  (
    "control(platform)",
    "the platform's control's API, and what an organization's copies down each day, v7v3w [B32]",
  ),
  (
    "blob",
    "the blob's interface: content put and read by its hash, a sweep, an archive, b8f35 [B32]",
  ),
  ("scope", "the scope's interface: what belongs to one, and its allowance, vuanj [B32]"),
  ("issuer", "the issuer's interface: a capability asked for and signed, vuanj [B32]"),
  (
    "executor",
    "the executor's interface: a code's hash, an input and a sandbox, given back an output or a panic, vuanj [B32]",
  ),
  ("backing", "the backing's interface: a scope's stores and what each declares, b8f35 [B32]"),
  (
    "extent",
    "the extent's interface: which pieces a content is made of and where each is packed, b8f35 [B32]",
  ),
  (
    "anchor",
    "the anchor's interface and its rows, a scope's id and where its backing is kept, b8f35 [B32]",
  ),
  (
    "copies",
    "a tablet's copies among themselves: WAL frames from a primary, a generation taken by a majority, vuanj [B32]",
  ),
]
