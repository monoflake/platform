/**
 * The control's organizations, opened by the operator, the thinnest the thread asks, RFC rxmd9.
 * Opening a label held answers the organization holding it and its secret, so a retry opens none.
 */
open Subset

let types: array<declared> = [
  // A label is lowercase letters, digits and hyphens, at most 63, as a name of DNS is.
  {
    name: "organization-open",
    def: Record([field("label", 1, Prim(#string))]),
    from: "rxmd9",
  },
  {
    name: "organization-opened",
    // The organization's token is `o<organization>.<secret>`, as JSON writes the two.
    def: Record([
      field("organization", 1, Id("organization")),
      optional("secret", 2, Prim(#secret)),
    ]),
    from: "rxmd9",
  },
]

let interface_: interface_ = {
  name: "organizations",
  version: 1,
  from: "rxmd9",
  operations: [op("open", "organization-open", "organization-opened", [("invalid", #rejected)])],
}
