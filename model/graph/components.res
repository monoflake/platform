/**
 * Every component and every library the drafts name, each component's dependencies as typed edges.
 * An edge says when it is needed and whether its loss is `hard` -- wrong or stopped -- or `soft` --
 * slower, staler, more garbage, never wrong. A `hard` edge points to its own layer or below; a
 * `soft` one may point up. A target beginning `?` is something the drafts need and no component is
 * yet: a boundary not drawn. Drafts: 13ixj storage, zn3u5 database, 49qyg functions, vuanj
 * components, b8f35 root and backing, wnqvu compat; v7v3w the two halves; 94y0d one platform on
 * another; 8lkuv the roles; the rules they are checked by, `docs/scope.md`. Every `hard`/`soft` here is
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
  /**
   * The ground and the operator are outside the design: trusted as written, never built. A role
   * is what this half needs of the platform half, built in another repository, RFC 8lkuv.
   */
  kind?: [#ground | #operator | #provided],
  /**
   * For a role, the contracts it answers, which every edge to it names; for what fills a role, the
   * contracts it implements.
   */
  answers?: array<string>,
  /** For a component another repository gives, the role it fills, RFC 8lkuv. */
  fills?: string,
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
  /** What of others' its code may take, as a library's, `model/graph/libraries.res`. */
  takes?: array<Libraries.taken>,
  /** The samples its code is held to, as a library's. */
  samples?: array<string>,
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
 * Of the components: `control(organization)` an organization's control, its products'
 * configuration as an HTTPS API, v7v3w; `footing(organization)` what the layer beneath gives it to
 * stand on, vr5lw; and the roles, what this half needs of the platform half, 8lkuv.
 */
let own: dict<component> = dict{
  "app": {
    layer: 1,
    half: #organization,
    edges: [
      {
        ...e("compute", #deploy, hard, "an app is deployed as functions, its types checked"),
        replaces: true,
      },
      e("compute", #serve, hard, "it runs as functions", ~contract=["wit"]),
      e("storage", #serve, hard, "the buckets it is bound to", ~contract=["storage"]),
      e("database", #serve, hard, "the database bound to it", ~contract=["database"]),
      e(
        "database",
        #deploy,
        hard,
        "a new version runs its build's migrations before it takes a call, the old serving on, zn3u5",
        ~contract=["database"],
        ~open_="whether the call graph also holds bindings is open, 49qyg [C11]",
      ),
      e(
        "control(organization)",
        #deploy,
        hard,
        "opens buckets and databases through its organization's control",
        ~contract=["configuration"],
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
        "authority",
        #deploy,
        hard,
        "its certificate, allowance, loans and status, pulled when it holds none and on a notice",
        ~contract=["?authority"],
      ),
      e(
        "authority",
        #deploy,
        hard,
        "its bundle's signing key, its alone, certified for seven days and renewed each day, v7v3w",
        ~contract=["?authority"],
      ),
      e(
        "driver(machine)",
        #deploy,
        hard,
        "applies the capacity it opens on each machine extension, vr5lw",
        ~contract=["management"],
      ),
      e(
        "driver(machine)",
        #deploy,
        hard,
        "deploys each version onto every host its placement chose, before it takes a call, vr5lw",
        ~contract=["deployments"],
      ),
      e(
        "driver(cloudflare)",
        #deploy,
        hard,
        "deploys each version onto the account its placement chose, before it takes a call, vr5lw",
        ~contract=["deployments"],
      ),
      e(
        "?builder",
        #deploy,
        hard,
        "where each version's code is fetched from by its hash, asked as configuration is applied, vr5lw",
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
      e("blob", #serve, hard, "content", ~contract=["blob"]),
      e(
        "footing(organization)",
        #serve,
        hard,
        "its scope's status and allowance, in the bundle, through scope*, vuanj",
        ~contract=["bundle.issuer"],
      ),
      key(),
      e(
        "blob",
        #background,
        soft,
        "sweep: bytes nothing names, hashes nothing counts",
        ~contract=["blob"],
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
    uses: ["capability*", "scope*", "compat*"],
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
      e(
        "footing(organization)",
        #serve,
        hard,
        "its scope's status and allowance, in the bundle, through scope*, vuanj",
        ~contract=["bundle.issuer"],
      ),
      key(),
    ],
    uses: ["capability*", "scope*", "compat*"],
  },
  "compute": {
    language: #rescript,
    layer: 0,
    half: #organization,
    edges: [
      replaced,
      e("?runner", #serve, hard, "where a tablet's writer and copies are"),
      e("issuer", #serve, hard, "a call's capabilities", ~contract=["issuer"]),
      e("executor", #serve, hard, "runs the code", ~contract=["executor"]),
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
      e("blob", #serve, soft, "derive outputs: a miss runs it again", ~contract=["blob"]),
      e(
        "footing(organization)",
        #deploy,
        hard,
        "the allowance a declaration must fit, and its scope's status, through scope*, vuanj",
        ~contract=["bundle.issuer"],
      ),
      e("?entry", #serve, hard, "a request trigger: HTTP reaches an app's function, 49qyg"),
      e("?entry", #deploy, hard, "binds an app's names, from the bundle, vr5lw"),
      key(),
      e("?clock", #serve, hard, "schedule fires at set times, queue retries wait between tries"),
      e("?clock", #deploy, hard, "writes an app's schedules, in the clock's format"),
    ],
    uses: ["capability*", "scope*", "vocabulary*", "wit*", "compat*"],
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
        "authority",
        #deploy,
        hard,
        "its signing key, certified for seven days and renewed each day, the certificate in the bundle and the key a secret deployed beside it, v7v3w",
        ~contract=["?authority"],
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
        ~contract=["blob"],
      ),
      e(
        "blob",
        #start,
        hard,
        "a copy added starts from its volume's last snapshot, then takes what is after from its primary, vuanj",
        ~contract=["blob"],
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
        "directory",
        #deploy,
        hard,
        "its scope's row, which names where its backing is kept, b8f35",
        ~contract=["?directory"],
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
  "root": {
    layer: -4,
    edges: [
      {...e("?source", #deploy, hard, "what it holds reaches each component"), replaces: true},
    ],
    uses: [],
  },
  /*
   * The roles the platform half fills, RFC 8lkuv: `authority`, what says an organization exists and
   * what it may use, RFC 7xpd3, and `directory`, what says where a scope's backing is, RFC 4dijn.
   */
  "authority": {
    layer: -3,
    kind: #provided,
    control: true,
    half: #platform,
    answers: ["?authority"],
    edges: [],
    uses: [],
  },
  "directory": {
    layer: -3,
    kind: #provided,
    half: #platform,
    answers: ["?directory"],
    edges: [],
    uses: [],
  },
  "footing(organization)": {layer: vendor, kind: #ground, half: #organization, edges: [], uses: []},
  "vendor": {layer: vendor, kind: #ground, edges: [], uses: []},
  "operator": {layer: vendor, kind: #operator, edges: [], uses: []},
}

/** What another repository gives this model, RFC 8lkuv: none when this one is checked alone. */
let given: dict<component> = Fill.part("components")->Option.getOr(Dict.make())

/** Each role filled, to the component filling it. */
let filler: dict<string> =
  given
  ->Dict.toArray
  ->Array.filterMap(((name, c)) => c.fills->Option.map(role => (role, name)))
  ->Dict.fromArray

/** A name as the whole graph knows it: a filled role by its filler, any other as it is. */
let named = name => filler->Dict.get(name)->Option.getOr(name)

/**
 * The whole graph of `own` and `given`: each role a component of `given` fills replaced by it, every
 * edge to the role pointed at its filler, and the rest of `given` beside.
 */
let merge = (own: dict<component>, given: dict<component>): dict<component> => {
  let filler =
    given
    ->Dict.toArray
    ->Array.filterMap(((name, c)) => c.fills->Option.map(role => (role, name)))
    ->Dict.fromArray
  let to_ = name => filler->Dict.get(name)->Option.getOr(name)
  own
  ->Dict.toArray
  ->Array.filter(((name, _)) => filler->Dict.get(name)->Option.isNone)
  ->Array.concat(given->Dict.toArray)
  // By name, so what the checks walk is the graph and not where each part was declared.
  ->Array.toSorted(((a, _), (b, _)) => a < b ? -1. : a > b ? 1. : 0.)
  ->Array.map(((name, c)) => (
    name,
    {...c, edges: c.edges->Array.map(edge => {...edge, to_: to_(edge.to_)})},
  ))
  ->Dict.fromArray
}

let components: dict<component> = merge(own, given)

let globalOpen: array<string> = []

/** Whether a component's code is another repository's, so none of it lies here, RFC fhg6w. */
let elsewhere = name => given->Dict.get(name)->Option.isSome

let permissive = "MIT OR Apache-2.0"

/**
 * The contracts an edge names that are not yet declared in the subset, by the name it gives each
 * after `?`, and the row that declares them. A tablet's copies speak among themselves -- WAL frames
 * from a primary, a generation taken by a majority, vuanj -- on no edge, as they are one component.
 */
let ownUndeclared: array<(string, string)> = [
  ("authority", "the record an organization's control pulls of its authority, signed, 7xpd3 [B32]"),
  ("backing", "the backing's interface: a scope's stores and what each declares, b8f35 [B32]"),
  (
    "extent",
    "the extent's interface: which pieces a content is made of and where each is packed, b8f35 [B32]",
  ),
  (
    "directory",
    "the directory's rows as they cross, signed: a scope's id, its status and where its backing is, 4dijn [B32]",
  ),
]

/** Every contract undeclared, with those the platform half's own components name, RFC 8lkuv. */
let undeclared = Array.concat(ownUndeclared, Fill.part("undeclared")->Option.getOr([]))
