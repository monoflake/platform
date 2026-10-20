/**
 * The bootstrap path, RFC 94y0d: what each version of the Platform can do, what each step runs, and
 * how each deployment came to it from the step before. `check.res` runs it in s0, on the correct
 * path alone; how a move fails, and the replicated log a database organization needs, are s1's.
 */
/**
 * What a deployment stands on: `provider` a machine a provider runs, `home` a machine the author
 * keeps at home, `foundation` the foundation platform's three products. Only `provider` offers
 * `instance`, 49qyg.
 */
type ground = [#cloudflare | #provider | #home | #foundation]

/** How a deployment came to a step from the one before. */
type move = [#"by hand" | #"new organization" | #rolling | #"planned stop" | #none]

type plan = [#free | #paid]

type deployment = {
  version: int,
  on: array<Versions.feature>,
  ground: array<ground>,
  move: move,
  /** The vendor's plan the deployment's Cloudflare account is on: the foundation platform's is paid
   * from step 0, RFC 94y0d. */
  plan?: plan,
}

type step = {
  what: string,
  foundation: deployment,
  production?: deployment,
  /** How production organizations are placed on foundation ones, RFC 94y0d. */
  cells?: [#"one each" | #"database organization"],
  /** Who uses the platform: the author and a friend or two unless others are invited, RFC 94y0d. */
  users?: [#author | #invited],
}

let foundation = (version, on, move) => {
  version,
  on,
  ground: [#cloudflare, #provider],
  move,
  plan: #paid,
}
let ownClouds: array<ground> = [#foundation, #cloudflare, #provider, #home]

let steps: array<step> = [
  {
    what: "v0 installed as the foundation platform, its own half by hand, its hosts bound as any host is",
    foundation: foundation(0, [#products, #hosts], #"by hand"),
  },
  {
    what: "v0 deployed again as the production platform, an organization on the foundation platform",
    foundation: foundation(0, [#products, #hosts], #none),
    production: {version: 0, on: [#products], ground: [#foundation], move: #"new organization"},
    cells: #"one each",
  },
  {
    what: "an upgrade by D3 built, the production platform moved to it",
    foundation: foundation(0, [#products, #hosts], #none),
    production: {
      version: 1,
      on: [#products, #rolling],
      ground: [#foundation],
      move: #"planned stop",
    },
    cells: #"one each",
  },
  {
    what: "the pin moved to v1",
    foundation: foundation(1, [#products, #hosts, #rolling], #"planned stop"),
    production: {version: 1, on: [#products, #rolling], ground: [#foundation], move: #none},
    cells: #"one each",
  },
  {
    what: "the deployer built",
    foundation: foundation(1, [#products, #hosts, #rolling], #none),
    production: {
      version: 2,
      on: [#products, #rolling, #deployer],
      ground: [#foundation],
      move: #rolling,
    },
    cells: #"one each",
  },
  {
    what: "the pin moved to v2",
    foundation: foundation(2, [#products, #hosts, #rolling, #deployer], #rolling),
    production: {
      version: 2,
      on: [#products, #rolling, #deployer],
      ground: [#foundation],
      move: #none,
    },
    cells: #"one each",
  },
  {
    what: "bringing one's own cloud, more vendors than one and metering built, proven on the author's own organizations",
    foundation: foundation(2, [#products, #hosts, #rolling, #deployer], #none),
    production: {
      version: 3,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering],
      ground: ownClouds,
      move: #rolling,
    },
    cells: #"one each",
  },
  {
    what: "the pin moved to v3: the foundation platform survives losing a vendor, and meters its use",
    foundation: foundation(
      3,
      [#products, #hosts, #rolling, #deployer, #vendors, #metering],
      #rolling,
    ),
    production: {
      version: 3,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering],
      ground: ownClouds,
      move: #none,
    },
    cells: #"one each",
  },
  {
    what: "others than the author and a friend or two invited to test, a checkpoint, once metering holds",
    foundation: foundation(3, [#products, #hosts, #rolling, #deployer, #vendors, #metering], #none),
    production: {
      version: 3,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering],
      ground: ownClouds,
      move: #none,
    },
    cells: #"one each",
    users: #invited,
  },
  {
    what: "a tablet's log replicated among hosts built, proven on the production platform",
    foundation: foundation(3, [#products, #hosts, #rolling, #deployer, #vendors, #metering], #none),
    production: {
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
    foundation: foundation(
      4,
      [#products, #hosts, #rolling, #deployer, #vendors, #metering, #replicated],
      #rolling,
    ),
    production: {
      version: 4,
      on: [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering, #replicated],
      ground: ownClouds,
      move: #none,
    },
    cells: #"database organization",
    users: #invited,
  },
]

/** How far the production platform's newest version may run ahead of the foundation's pin. */
let window = 1

/** How many planned stops the bootstrap may take in all, RFC 94y0d. */
let stops = 5
