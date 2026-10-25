/**
 * A private address an organization's own control reaches a host at, its tunnel made by this
 * control, RFC rxmd9. Only an organization opens one, and only it is relayed to that address.
 */
open Subset

let types: array<declared> = [
  {name: "reach-open", def: Record([]), from: "rxmd9"},
  // The address is the platform's, so no two organizations' hosts share one.
  {
    name: "reach-opened",
    def: Record([
      field("reach", 1, Id("capacity")),
      field("address", 2, Prim(#string)),
      optional("tunnel", 3, Prim(#secret)),
    ]),
    from: "rxmd9",
  },
]

/** A tunnel that cannot be made is `unreachable`, and the caller retries. */
let interface_: interface_ = {
  name: "reaches",
  version: 1,
  from: "rxmd9",
  operations: [
    op(
      "open",
      "reach-open",
      "reach-opened",
      [("unreachable", #unavailable), ("no_address", #rejected)],
      ~callers=[#organization],
    ),
  ],
}
