/**
 * The bootstrap path, RFC 94y0d: what each version of the Platform can do, what each step runs, and
 * how each deployment came to it from the step before. `check.res` runs it in s0, on the correct
 * path alone; how a move fails, and the replicated log a database organization needs, are s1's.
 */
/**
 * What a deployment stands on: `provider` a machine a provider runs, `home` a machine the author
 * keeps at home, `internal` the internal platform's three products. Only `provider` offers
 * `instance`, 49qyg.
 */
type ground = [#cloudflare | #provider | #home | #internal]

/** How a deployment came to a step from the one before. */
type move = [#"by hand" | #"new organization" | #rolling | #"planned stop" | #none]

type plan = [#free | #paid]

type deployment = {
  version: int,
  on: array<Versions.feature>,
  ground: array<ground>,
  move: move,
  /** The vendor's plan the deployment's Cloudflare account is on: the internal platform's is paid
   * from step 0, RFC 94y0d. */
  plan?: plan,
}

type step = {
  what: string,
  internal: deployment,
  external_?: deployment,
  /** How external organizations are placed on internal ones, RFC 94y0d. */
  cells?: [#"one each" | #"database organization"],
  /** Who uses the platform: the author and a friend or two unless others are invited, RFC 94y0d. */
  users?: [#author | #invited],
}

let internal = (version, on, move) => {
  version,
  on,
  ground: [#cloudflare, #provider],
  move,
  plan: #paid,
}
let ownClouds: array<ground> = [#internal, #cloudflare, #provider, #home]

let steps: array<step> = [
  {
    what: "v0 installed as the internal platform, its own half by hand, its hosts bound as any host is",
    internal: internal(0, [#products, #hosts], #"by hand"),
  },
  {
    what: "v0 deployed again as the external platform, an organization on the internal one",
    internal: internal(0, [#products, #hosts], #none),
    external_: {version: 0, on: [#products], ground: [#internal], move: #"new organization"},
    cells: #"one each",
  },
  {
    what: "an upgrade by D3 built, the external platform moved to it",
    internal: internal(0, [#products, #hosts], #none),
    external_: {version: 1, on: [#products, #rolling], ground: [#internal], move: #"planned stop"},
    cells: #"one each",
  },
  {
    what: "the pin moved to v1",
    internal: internal(1, [#products, #hosts, #rolling], #"planned stop"),
    external_: {version: 1, on: [#products, #rolling], ground: [#internal], move: #none},
    cells: #"one each",
  },
  {
    what: "the deployer built",
    internal: internal(1, [#products, #hosts, #rolling], #none),
    external_: {
      version: 2,
      on: [#products, #rolling, #deployer],
      ground: [#internal],
      move: #rolling,
    },
    cells: #"one each",
  },
  {
    what: "the pin moved to v2",
    internal: internal(2, [#products, #hosts, #rolling, #deployer], #rolling),
    external_: {version: 2, on: [#products, #rolling, #deployer], ground: [#internal], move: #none},
    cells: #"one each",
  },
  {
    what: "bringing one's own cloud, more vendors than one and metering built, proven on the author's own organizations",
    internal: internal(2, [#products, #hosts, #rolling, #deployer], #none),
    external_: {
      version: 3,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering],
      ground: ownClouds,
      move: #rolling,
    },
    cells: #"one each",
  },
  {
    what: "the pin moved to v3: the internal platform survives losing a vendor, and meters its use",
    internal: internal(3, [#products, #hosts, #rolling, #deployer, #vendors, #metering], #rolling),
    external_: {
      version: 3,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering],
      ground: ownClouds,
      move: #none,
    },
    cells: #"one each",
  },
  {
    what: "others than the author and a friend or two invited to test, a checkpoint, once metering holds",
    internal: internal(3, [#products, #hosts, #rolling, #deployer, #vendors, #metering], #none),
    external_: {
      version: 3,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering],
      ground: ownClouds,
      move: #none,
    },
    cells: #"one each",
    users: #invited,
  },
  {
    what: "a tablet's log replicated among hosts built, proven on the external platform",
    internal: internal(3, [#products, #hosts, #rolling, #deployer, #vendors, #metering], #none),
    external_: {
      version: 4,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering, #replicated],
      ground: ownClouds,
      move: #rolling,
    },
    cells: #"one each",
    users: #invited,
  },
  {
    what: "the pin moved to v4: cells move onto a database organization",
    internal: internal(
      4,
      [#products, #hosts, #rolling, #deployer, #vendors, #metering, #replicated],
      #rolling,
    ),
    external_: {
      version: 4,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering, #replicated],
      ground: ownClouds,
      move: #none,
    },
    cells: #"database organization",
    users: #invited,
  },
]

/** How far the external platform's newest version may run ahead of the internal's pin. */
let window = 1

/** How many planned stops the bootstrap may take in all, RFC 94y0d. */
let stops = 5
