/**
 * Every boundary, and the contract it must keep once written: what it provides, and what the
 * dimensions require of it through the components that need it. Without a contract an edge to it is
 * a violation; with one it is an assumption the next layer down must keep. See `docs/scope.md`.
 */
type boundary = {
  contract?: string,
  /** Who keeps the contract, once the layer beneath has said; absent while it is undecided. */
  keptBy?: string,
  /** Decided now, since a mistake is written into data; by hand on day one; or later. */
  triage?: [#"decided now" | #"by hand on day one" | #later],
  /** Which half keeps it, where one does, RFC v7v3w. */
  half?: Components.half,
}

let boundaries: dict<boundary> = dict{
  "?deployer": {
    half: #platform,
    keptBy: "the operator, standing on the ground: on day one the deployment the operator runs by hand, since what replaces every component can stand on none of them",
    triage: #"by hand on day one",
    contract: "installs each component the first time, in the order bootstrap allows, and replaces one component's build by a new one while the rest run, one component at a time. It keeps which build runs where and the version range each reads, on disk, so a planned restart brings each component back at the build recorded, and computes the version each format is written at, wnqvu. Before a replacement it checks the new build reads what its neighbors write now and they read what it will write, and refuses naming the format when either fails. Replacing a component never needs that component, so neither its records nor the builds it delivers rest on any component it replaces. It reads a build's manifest, in compat's format, and carries the build unread. It reads where a component may go from the roster. It starts from the ground and the operator alone; the operator installs it and replaces it. It is the control plane's: while it is lost, everything running goes on running",
  },
  "?entry": {
    half: #organization,
    keptBy: "the organization's half: a request comes in by the resources bound to the organization, a node's network or a third-party account the platform operates through its API, v7v3w; on day one the operator binds each name by hand in the organization's account",
    triage: #"by hand on day one",
    contract: "an HTTP request for a name is delivered to what the name is bound to -- an app's request function, as a call through the function product, or the storage, which answers an object -- and its response returned. It is the name and nothing more, vr5lw: on a machine a listener its driver deploys, as it deploys an adapter, ends TLS with the machine's certificate and hands the request to the deployment bound, and a Worker is its own entry; no route table stands beside the names, which the organization's control binds in its bundle. It reads the name alone, carrying the rest of a request unread, but for one path: while it holds a challenge's id unanswered, a few seconds, it answers /.well-known/monoflake-challenge/{id} itself, vr5lw. It starts without the function product or the storage running and answers unavailable while what a name is bound to is down; it is the data plane's, and never authenticates an app's users; an organization's gateway, its own and never an app, is bound to its platform name and routes by path, vr5lw. Who may read a private link is open, 13ixj [C10]",
  },
  "?clock": {
    half: #organization,
    keptBy: "the organization's half: its table is configuration the platform keeps and copies down, and each tick is fired by the scheduler of the resource bound to the organization it fires on, written there at deployment, the platform firing it only where a resource has none, v7v3w; later: until it is built no schedule or retry is offered, and the storage's sweep waits, which costs only garbage kept longer",
    triage: #later,
    contract: "at the times a schedule sets, and once at a time asked for, a tick is delivered to the component that wrote it -- a function's schedule, a queue's retry, the storage's sweep. It delivers by a table of schedules and timers in its own format, written by that component, at deployment for a schedule; a tick carries only the row's id, unread. Times missed are merged in it, one tick pending per schedule however many passed. A tick is delivered at least once, never exactly once; the component it reaches drops a repeat by the schedule and the time it was due. Its table is kept in the footing, so a restart loses no schedule; it starts without anything it delivers to. How precise its times are is open [C14]",
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
    contract: "places each tablet's writer and read copies at run time, on places the roster lists that offer instance, 49qyg, and answers where a tablet's writer and copies are now; it decides when a writer is handed over. Placing a tablet the configuration names is the data plane's, so it goes on while the control plane is lost; creating a database is configuration, the control plane's, zn3u5. It promises at least one writer, never exactly one: two may be placed for a moment, and the vendor, or the generation a majority of a tablet's copies took, refuses all but one, vuanj. Its record of which copies hold a tablet on machines is the footing's `writer` row and never in a tablet, which needs it to start, and a planned restart brings each tablet back where it was. It reads only that record, never a tablet's contents. Keyed daemons, one per key, may come to be placed the same way, 49qyg",
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
    contract: "what the root holds reaches each component that reads it: the root public key every component in both halves, the organization's inside what the platform deploys there; the intermediate's key and certificate, the masters, the platform's own stores and their secrets, and the roster of the platform's own vendor accounts, the platform's half alone. All but the root private key and the masters' shares, held offline, is kept on the platform's own vendor accounts as secrets deployed with the components that read them, through a vendor contract the platform writes, never in a repository or in a store the platform runs, which needs them to start. A change is the operator's, by hand, and deploys again what reads it. It is the control plane's: while it is lost, every component keeps what it was given",
  },
}
