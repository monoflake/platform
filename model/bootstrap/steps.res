/**
 * The bootstrap path's shape, RFC 94y0d: what each step runs and how each deployment came to it from
 * the step before. The path is the hosted platform's, monoflake/cloud's, RFC 8lkuv, and is checked
 * where it is given; how a move fails, and how a tablet's copies fail, are s1's.
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

/** The path itself, the hosted platform's: its steps, the window and the stops, RFC 8lkuv. */
type path = {steps: array<step>, window: int, stops: int}

let path: option<path> = Fill.part("path")

/** Each step of the path, none when this model is checked alone. */
let steps = path->Option.mapOr([], p => p.steps)

/** How far the production platform's newest version may run ahead of the foundation's pin. */
let window = path->Option.mapOr(0, p => p.window)

/** How many planned stops the bootstrap may take in all, RFC 94y0d. */
let stops = path->Option.mapOr(0, p => p.stops)
