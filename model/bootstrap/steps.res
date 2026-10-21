/**
 * A deployment of the Platform as a path of steps reads one, RFC 94y0d. Which deployments there are
 * and their path are the hosted platform's, RFC 8lkuv.
 */
/**
 * What a deployment stands on, the vendor's own, a provider's machine, its operator's machine or
 * another platform's three products. Only `provider` offers `instance`, 49qyg.
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
