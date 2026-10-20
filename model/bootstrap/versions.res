/** What each version of the Platform can do, RFC 94y0d. */
/**
 * What a version of the Platform can do. A deployment turns on some of what its version has:
 * `products`, the three products, standing on a footing; `hosts`, a machine a provider runs, bound
 * as a host by the ordinary flow, its commands the operator's; `rolling`, an upgrade by D3, one component
 * replaced while the rest run; `deployer`, the deployer, in place of day one's commands; `byoc`, a
 * user binding a cloud of their own; `vendors`, an organization's extensions spread over vendors, so
 * losing one is survived; `metering`, what each resource is used for counted, and cut off short of a
 * limit, RFC 94y0d. A tablet's copies on machines are v0's own, RFC vuanj, so no version waits on
 * them.
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
