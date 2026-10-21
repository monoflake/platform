/** What each version of the Platform can do, RFC 94y0d. */
/**
 * What a version of the Platform can do, of which a deployment turns some on, RFC 94y0d. A tablet's
 * copies on machines are v0's own, RFC vuanj.
 */
type feature = [
  | #products
  | #hosts
  | #rolling
  | #deployer
  | #byoc
  | #vendors
  | #metering
]

/** What each version has, by its number. */
let versions: array<array<feature>> = [
  [#products, #hosts],
  [#products, #hosts, #rolling],
  [#products, #hosts, #rolling, #deployer],
  [#products, #hosts, #rolling, #deployer, #byoc, #vendors, #metering],
]
