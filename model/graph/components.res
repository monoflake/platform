/**
 * Every component and library the drafts name, with typed edges whose loss is `hard` or `soft`. A
 * target led by `?` is a boundary not drawn, `docs/scope.md`.
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
  /** Who defines the format the source reads across this edge, when it is not the target. */
  reads?: string,
  /** Whether this edge is how its component is itself replaced by a new version, D3. */
  replaces?: bool,
  /**
   * What crosses this edge between two processes, a contract of `model/contracts/`, `wit`, or
   * `?{name}` not yet declared, RFC fhg6w.
   */
  contract?: array<string>,
}

type component = {
  layer: int,
  /**
   * The ground and the operator are outside the design, trusted as written. A role is built in
   * another repository, RFC 8lkuv.
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
   * Whether it is a control, the HTTPS API that alone writes configuration, v7v3w. A footing is the
   * same word of either half, vr5lw.
   */
  control?: bool,
  /** Whether the platform runs it as an owner, in an organization of its own, RFC vuanj. */
  asOwner?: bool,
  /** Which half runs it, RFC v7v3w; the root runs nothing, so it has none. */
  half?: half,
  /**
   * The language its code is written in, ReScript for what runs on a Worker and Rust for what runs
   * natively, RFC fhg6w. None where the code is not the platform's.
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
 * The organization's control, its footing and the roles this half needs of the platform half,
 * v7v3w, vr5lw and 8lkuv.
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
        ~contract=["footing", "records", "bundle"],
      ),
      e(
        "authority",
        #deploy,
        hard,
        "its certificate, allowance, loans and status, pulled when it holds none and on a notice",
        ~contract=["authority"],
      ),
      e(
        "authority",
        #deploy,
        hard,
        "its bundle's signing key, its alone, certified for seven days and renewed each day, v7v3w",
        ~contract=["authority"],
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
        ~contract=["footing", "bundle.storage"],
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
        ~contract=["footing", "bundle.issuer"],
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
        ~contract=["footing", "bundle.database"],
      ),
      e("tablet", #serve, hard, "a database is a tablet", ~contract=["database"]),
      e(
        "footing(organization)",
        #serve,
        hard,
        "its scope's status and allowance, in the bundle, through scope*, vuanj",
        ~contract=["footing", "bundle.issuer"],
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
        ~contract=["footing", "bundle.compute"],
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
        #background,
        soft,
        "a tick's lease, so one compute of several fires it, v7v3w",
        ~contract=["footing", "record.lease"],
      ),
      e(
        "footing(organization)",
        #deploy,
        hard,
        "the allowance a declaration must fit, and its scope's status, through scope*, vuanj",
        ~contract=["footing", "bundle.issuer"],
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
        ~contract=["footing", "bundle.issuer"],
      ),
      e(
        "authority",
        #deploy,
        hard,
        "its signing key, certified for seven days and renewed each day, the certificate in the bundle and the key a secret deployed beside it, v7v3w",
        ~contract=["authority"],
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
        "footing(organization)",
        #start,
        hard,
        "which copies hold a tablet on machines, its primary and generation, raised only as one is taken over, vuanj",
        ~contract=["footing", "record.writer"],
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
      e(
        "directory",
        #deploy,
        hard,
        "where its scope's backing is kept, read as it is deployed and only then, 4dijn",
        ~contract=["directory"],
      ),
      e(
        "footing(organization)",
        #serve,
        hard,
        "the scope's stores, the bundle's backing section; the extent's records it reads and writes itself, and which journal each placement writes, b8f35",
        ~contract=[
          "footing",
          "bundle.backing",
          "record.content",
          "record.piece",
          "record.parcel",
          "record.journal",
        ],
      ),
      e(
        "driver(machine)",
        #serve,
        hard,
        "parcels and journals put to the scope's stores through the object kind, a call signed by its certificate, b8f35",
        ~contract=["object"],
      ),
      e(
        "driver(cloudflare)",
        #serve,
        hard,
        "parcels and journals put to the scope's stores through the object kind, a call signed by its certificate, b8f35",
        ~contract=["object"],
      ),
      e(
        "root",
        #start,
        hard,
        "a scope's salt and key, derived from the masters and deployed beside it as secrets, never in the bundle, v7v3w",
        ~contract=["deployments"],
      ),
      key(),
      e("?clock", #background, soft, "paces a rekey the control plane started, b8f35"),
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
  "extent": {
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
        "where its scope's backing is kept, read as it is deployed and only then, 4dijn",
        ~contract=["directory"],
      ),
      e(
        "footing(organization)",
        #serve,
        hard,
        "the extent's records and the scope's stores, the bundle's backing section, b8f35",
        ~contract=["footing", "record.content", "record.piece", "record.parcel", "bundle.backing"],
      ),
      e(
        "driver(machine)",
        #background,
        hard,
        "parcels moved between stores through the object kind, a call signed by its certificate, holding no key, b8f35",
        ~contract=["object"],
      ),
      e(
        "driver(cloudflare)",
        #background,
        hard,
        "parcels moved between stores through the object kind, a call signed by its certificate, holding no key, b8f35",
        ~contract=["object"],
      ),
      e(
        "root",
        #start,
        hard,
        "its certificate and the root's public key, deployed, b8f35",
        ~contract=["certificate"],
      ),
      e("?clock", #background, soft, "paces its walk of every parcel, b8f35"),
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
   * The roles the platform half fills, `authority`, RFC 7xpd3, and `directory`, RFC 4dijn, RFC
   * 8lkuv.
   */
  "authority": {
    layer: -3,
    kind: #provided,
    control: true,
    half: #platform,
    answers: ["authority"],
    edges: [],
    uses: [],
  },
  "directory": {
    layer: -3,
    kind: #provided,
    half: #platform,
    answers: ["directory"],
    edges: [],
    uses: [],
  },
  "footing(organization)": {layer: vendor, kind: #ground, half: #organization, edges: [], uses: []},
  "vendor": {layer: vendor, kind: #ground, edges: [], uses: []},
  "operator": {layer: vendor, kind: #operator, edges: [], uses: []},
}

/** What another repository gives this model, none when this one is checked alone, RFC 8lkuv. */
let given: dict<component> = Fill.part("components")->Option.getOr(Dict.make())

/** Each role filled, to the component filling it. */
let filler: dict<string> =
  given
  ->Dict.toArray
  ->Array.filterMap(((name, c)) => c.fills->Option.map(role => (role, name)))
  ->Dict.fromArray

/** A name as the whole graph knows it, a filled role by its filler. */
let named = name => filler->Dict.get(name)->Option.getOr(name)

/**
 * The whole graph of `own` and `given`, each role replaced by its filler in `given` and every edge
 * to it repointed.
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
 * The contracts an edge names that the subset does not declare yet, by the name after `?`, and the
 * row that declares each.
 */
let ownUndeclared: array<(string, string)> = []

/** Every contract undeclared, with those the platform half's own components name, RFC 8lkuv. */
let undeclared = Array.concat(ownUndeclared, Fill.part("undeclared")->Option.getOr([]))
