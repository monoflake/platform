/**
 * Every part and every library the drafts name, each part's dependencies as typed edges. An edge
 * says when it is needed and whether its loss is `hard` -- wrong or stopped -- or `soft` -- slower,
 * staler, more garbage, never wrong. A `hard` edge points to its own layer or below; a `soft` one
 * may point up. A target beginning `?` is something the drafts need and no part is yet: a boundary
 * not drawn. Drafts: 13ixj storage, zn3u5 database, 49qyg functions, vuanj parts, b8f35 root and
 * backing, wnqvu compat; v7v3w the two halves; 94y0d the internal and external platforms; the rules
 * they are checked by, `scope.md`. Every `hard`/`soft` here is proposed, not decided; `open_` marks
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
   * carried unread is no one's to name here: a tablet holding another part's rows reads none of them.
   */
  reads?: string,
  /** Whether this edge is how its part is itself replaced by a new version, D3. */
  replaces?: bool,
}

type part = {
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
  edges: array<edge>,
  uses: array<string>,
}

type library = {
  what: string,
  /** Whether its output must agree between parts, so its version goes into what it writes. */
  agrees: bool,
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
 * Of the parts: `console` is a dashboard in an ordinary organization named `console`, holding no
 * privilege, v7v3w; `control(organization)` an organization's control, its products' configuration
 * as an HTTPS API, v7v3w; `control(platform)` the platform's, what spans organizations, as an HTTPS
 * API in no organization, v7v3w; `footing(organization)` and `footing(platform)` what the platform,
 * or the layer beneath, gives a control to stand on, vr5lw.
 */
let parts: dict<part> = dict{
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
        ~open_="that interface is no part, 49qyg [C14]",
      ),
    ],
    uses: ["vocabulary*", "compat*"],
  },
  "backing": {
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
    layer: -2,
    half: #organization,
    edges: [replaced, e("vendor", #serve, hard, "runs sandboxes on a machine or a runtime")],
    uses: ["vocabulary*", "compat*"],
  },
  "anchor": {
    layer: -3,
    keeps: true,
    half: #platform,
    edges: [replaced, e("footing(platform)", #serve, hard, "its rows, in the platform's footing")],
    uses: ["compat*"],
  },
  "control(platform)": {
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
    edges: [{...e("?source", #deploy, hard, "what it holds reaches each part"), replaces: true}],
    uses: [],
  },
  "footing(organization)": {layer: vendor, kind: #ground, half: #organization, edges: [], uses: []},
  "footing(platform)": {layer: vendor, kind: #ground, half: #platform, edges: [], uses: []},
  "vendor": {layer: vendor, kind: #ground, edges: [], uses: []},
  "operator": {layer: vendor, kind: #operator, edges: [], uses: []},
}

/**
 * Every boundary, and the contract it must keep once written: what it provides, and what the
 * dimensions require of it through the parts that need it. Without a contract an edge to it is a
 * violation; with one it is an assumption the next layer down must keep. See `scope.md`.
 */
type boundary = {
  contract?: string,
  /** Who keeps the contract, once the layer beneath has said; absent while it is undecided. */
  keptBy?: string,
  /** Decided now, since a mistake is written into data; by hand on day one; or later. */
  triage?: [#"decided now" | #"by hand on day one" | #later],
  /** Which half keeps it, where one does, RFC v7v3w. */
  half?: half,
}

let boundaries: dict<boundary> = dict{
  "?deployer": {
    half: #platform,
    keptBy: "the operator, standing on the ground: on day one the deployment the operator runs by hand, since what replaces every part can stand on none of them",
    triage: #"by hand on day one",
    contract: "installs each part the first time, in the order bootstrap allows, and replaces one part's build by a new one while the rest run, one part at a time. It keeps which build runs where and the version range each reads, on disk, so a planned restart brings each part back at the build recorded, and computes the version each format is written at, wnqvu. Before a replacement it checks the new build reads what its neighbors write now and they read what it will write, and refuses naming the format when either fails. Replacing a part never needs that part, so neither its records nor the builds it delivers rest on any part it replaces. It reads a build's manifest, in compat's format, and carries the build unread. It reads where a part may go from the roster. It starts from the ground and the operator alone; the operator installs it and replaces it. It is the control plane's: while it is lost, everything running goes on running",
  },
  "?entry": {
    half: #organization,
    keptBy: "the organization's half: a request comes in by the resources bound to the organization, a node's network or a third-party account the platform operates through its API, v7v3w; on day one the operator binds each name by hand in the organization's account",
    triage: #"by hand on day one",
    contract: "an HTTP request for a name is delivered to what the name is bound to -- an app's request function, as a call through the function product, or the storage, which answers an object -- and its response returned. It is the name and nothing more, vr5lw: on a machine a listener its driver deploys, as it deploys an adapter, ends TLS with the machine's certificate and hands the request to the deployment bound, and a Worker is its own entry; no route table stands beside the names, which the organization's control binds in its bundle. It reads the name alone, carrying the rest of a request unread. It starts without the function product or the storage running and answers unavailable while what a name is bound to is down; it is the data plane's, and never authenticates an app's users; an organization's gateway, its own and never an app, is bound to its platform name and routes by path, vr5lw. Who may read a private link is open, 13ixj [C10]",
  },
  "?clock": {
    half: #organization,
    keptBy: "the organization's half: its table is configuration the platform keeps and copies down, and each tick is fired by the scheduler of the resource bound to the organization it fires on, written there at deployment, the platform firing it only where a resource has none, v7v3w; later: until it is built no schedule or retry is offered, and the storage's sweep waits, which costs only garbage kept longer",
    triage: #later,
    contract: "at the times a schedule sets, and once at a time asked for, a tick is delivered to the part that wrote it -- a function's schedule, a queue's retry, the storage's sweep. It delivers by a table of schedules and timers in its own format, written by that part, at deployment for a schedule; a tick carries only the row's id, unread. Times missed are merged in it, one tick pending per schedule however many passed. A tick is delivered at least once, never exactly once; the part it reaches drops a repeat by the schedule and the time it was due. Its table is kept in the footing, so a restart loses no schedule; it starts without anything it delivers to. How precise its times are is open [C14]",
  },
  "?intermediate": {
    half: #platform,
    keptBy: "the platform's half, since what it holds spans organizations; it certifies each organization's own signing key for seven days and renews it every day, v7v3w; on day one the operator certifies the intermediate with the root private key, and renews each organization's certificate every day, by hand",
    triage: #"by hand on day one",
    contract: "certifies each new working key the issuer gives it, with an expiry, in a chain to the root,. Its own private key and the certificate the root signed for it come from what the root delivers, put there by the operator. It is the platform's half's: an organization's issuer signs on without it for seven days, and it is needed once a day and never on a call. It starts without the issuer; its key and certificate are kept as secrets on disk; its program is replaced by the deployer. The intermediate key itself is rotated by the operator, offline, with the root private key. Open: how often it is rotated; whether a system apart from the platform, such as a machine the author keeps, may rotate it unattended on the author's authority; how a leaked intermediate key is revoked, s1's; how long a working key lives [D3]",
  },
  "?runner": {
    half: #organization,
    keptBy: "the organization's half: placement decides at run time by a policy the platform keeps and copies down, on the resources bound to the organization, v7v3w; on day one the operator pins each database's writer to one resource by hand",
    triage: #"by hand on day one",
    contract: "places each tablet's writer and read copies at run time, on places the roster lists that offer instance, 49qyg, and answers where a tablet's writer and copies are now; it decides when a writer is handed over. Placing a tablet the configuration names is the data plane's, so it goes on while the control plane is lost; creating a database is configuration, the control plane's, zn3u5. It promises at least one writer, never exactly one: two may be placed for a moment, and the generation the footing keeps refuses all but one, vuanj. Its record of what is placed where is kept in the footing and never in a tablet, which needs it to start, and a planned restart brings each tablet back where it was. It reads only that record, never a tablet's contents. Keyed daemons, one per key, may come to be placed the same way, 49qyg",
  },
  "?roster": {
    keptBy: "the operator: on day one a static list of hosts, delivered with what the root delivers, ?source; what each offers, each host reports itself, b8f35; the places an organization's work may go are the resources bound to it, v7v3w",
    triage: #"by hand on day one",
    contract: "lists the places that can run something, each with its address and what it offers, in the vocabulary of capabilities -- the sandboxes, the network and the rest, 49qyg. The executor, the runner and the deployer read it. Reading it is the data plane's: while the control plane is lost, the last list is still read. Changing it, a place added or removed, is the control plane's, and on day one the operator's. The list is kept on disk, and it is up before any of its readers",
  },
  "?egress": {
    half: #organization,
    keptBy: "the organization's half: a request leaves by the resource its call runs on, a node's network or a third-party account, v7v3w; later: until the check is built into what the platform deploys, a request leaves unchecked, which on an organization's own resources costs only the guard",
    triage: #later,
    contract: "an effect's HTTP request to the world leaves through it, and the response returns. Each request carries a capability showing its call declared network http, and it checks it, trusting no caller. It reads an HTTP request's envelope -- where it goes, its method, its headers -- whose format is a published standard, the ground's; bodies are carried unread. It sees each request's destination and size and limits them by the scope's allowance; what it counts to limit is soft, so a restart that loses it loosens a limit for a moment and keeps nothing on disk; the amounts are open [C14]. Only http goes through it: tcp, udp and icmp leave from the host that offers them, as the roster lists. It starts without the executor or the function product, and is the data plane's: while the control plane is lost, effects still reach the world",
  },
  "?builder": {
    half: #organization,
    keptBy: "what builds for the organization's target, vr5lw: Cloudflare's own builds for a Worker, GitHub Actions in the user's repository, the platform's CI once it is; on day one the operator's GitHub Actions",
    triage: #"by hand on day one",
    contract: "given an app's commit at its Git provider, a target, a sandbox and an architecture, it builds the code in that sandbox's own form and keeps it for as long as it keeps what it builds, answering its hash and, asked, an address the bytes are fetched from by a driver. Once it no longer keeps a version, the version is built again from its commit, and may differ. An artifact is fetched once, as it is deployed, and a start reads only what its host holds. It is the control plane's: what runs keeps running from what its host holds, and a machine keeps the version it replaced until the new one serves",
  },
  "?source": {
    keptBy: "the operator, standing on the ground: the root private key and the masters' shares held offline by hand, and the rest deployed by the operator as secrets on the platform's own vendor accounts, b8f35",
    triage: #"by hand on day one",
    contract: "what the root holds reaches each part that reads it: the root public key every part in both halves, the organization's inside what the platform deploys there; the intermediate's key and certificate, the masters, the platform's own stores and their secrets, and the roster of the platform's own vendor accounts, the platform's half alone. All but the root private key and the masters' shares, held offline, is kept on the platform's own vendor accounts as secrets deployed with the parts that read them, through a vendor contract the platform writes, never in a repository or in a store the platform runs, which needs them to start. A change is the operator's, by hand, and deploys again what reads it. It is the control plane's: while it is lost, every part keeps what it was given",
  },
}

/**
 * A kind of record, the half its truth is kept in, and the parts that write it. A record a control
 * writes is configuration: the platform's control for what spans organizations, an organization's
 * for its products'; data is what lives inside what was opened, v7v3w. `check.res` refuses
 * configuration any other part writes, since the data plane runs on while a control is lost,
 * `scope.md`, and a record of the platform's half any part of an organization's writes.
 */
type held = {
  half: half,
  writes: array<string>,
  from: string,
}

let records: dict<held> = dict{
  "bucket": {half: #organization, writes: ["control(organization)"], from: "13ixj, v7v3w"},
  "database": {half: #organization, writes: ["control(organization)"], from: "zn3u5, v7v3w"},
  "app": {half: #organization, writes: ["control(organization)"], from: "49qyg, v7v3w"},
  "grant": {half: #organization, writes: ["control(organization)"], from: "vuanj, v7v3w"},
  "name": {half: #organization, writes: ["control(organization)"], from: "vr5lw"},
  "member": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "invitation": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "organization": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "tree": {half: #organization, writes: ["control(organization)"], from: "v7v3w"},
  "scope": {half: #organization, writes: ["control(organization)"], from: "vr5lw"},
  "extension(platform)": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "extension(organization)": {
    half: #organization,
    writes: ["control(organization)"],
    from: "v7v3w",
  },
  "lease": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "account": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "organization(platform)": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "label": {half: #platform, writes: ["control(platform)"], from: "v7v3w, vr5lw"},
  "username": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "sign-in": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "membership": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "domain": {half: #platform, writes: ["control(platform)"], from: "vr5lw"},
  "certificate": {half: #platform, writes: ["control(platform)"], from: "v7v3w"},
  "allowance": {half: #platform, writes: ["control(platform)"], from: "vuanj"},
  "file": {half: #organization, writes: ["storage"], from: "13ixj"},
  "row": {half: #organization, writes: ["database"], from: "zn3u5"},
  "log": {half: #organization, writes: ["tablet"], from: "vuanj"},
  "extent": {half: #organization, writes: ["blob"], from: "b8f35"},
  "call": {half: #organization, writes: ["compute"], from: "49qyg"},
  "message": {half: #organization, writes: ["compute"], from: "49qyg"},
  "repeat": {half: #organization, writes: ["compute"], from: "49qyg, v7v3w"},
}

let globalOpen: array<string> = []

let libraries: dict<library> = dict{
  "compat*": {
    what: "versions: a frozen core, and ranges, features and refusals on it, wnqvu",
    agrees: true,
    uses: [],
  },
  "capability*": {
    what: "a capability and its chain to the root, checked, vuanj",
    agrees: false,
    uses: ["compat*"],
  },
  "vocabulary*": {
    what: "capabilities by name, type and rule; declared, allowed, offered compared, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "placement*": {
    what: "where anything is placed among what meets its needs, scored by rendezvous over each one's weight: a parcel among stores, a deployment among hosts, b8f35, vr5lw",
    agrees: true,
    uses: ["compat*"],
  },
  "layout*": {
    what: "content cut by FastCDC into pieces, packed into parcels, parity, b8f35",
    agrees: true,
    uses: ["compat*"],
  },
  "keys*": {
    what: "a scope's salt and key, derived from the masters and its id, b8f35",
    agrees: true,
    uses: ["compat*"],
  },
  "wit*": {
    what: "an export's types, and a call checked against them, 49qyg",
    agrees: false,
    uses: ["compat*"],
  },
  "extensions*": {
    what: "a control's extensions: each host's binding, its credentials, quota, levels and grace, the networks its hosts may use, the capacity lists sent to drivers, and what it leases, the same code in both controls, v7v3w",
    agrees: false,
    uses: ["compat*"],
  },
  "sqlite*": {what: "the engine a tablet runs", agrees: false, uses: []},
}
