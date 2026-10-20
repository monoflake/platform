/**
 * What a deployment of the Platform is, as a path of steps reads one, RFC 94y0d: its version, what of
 * it is on, what it stands on, and how it came to its step. Which deployments there are, and the path
 * they take, is the hosted platform's, RFC 8lkuv.
 */
/**
 * What a deployment stands on: `cloudflare` the vendor's own, `provider` a machine a provider runs,
 * `home` a machine its operator keeps, `platform` another platform's three products, as one platform
 * stands on another as on a vendor. Only `provider` offers `instance`, 49qyg.
 */
type ground = [#cloudflare | #provider | #home | #platform]

/** How a deployment came to a step from the one before. */
type move = [#"by hand" | #"new organization" | #rolling | #"planned stop" | #none]

type plan = [#free | #paid]

type deployment = {
  version: int,
  on: array<Versions.feature>,
  ground: array<ground>,
  move: move,
  /** The vendor's plan its Cloudflare account is on. */
  plan?: plan,
}
