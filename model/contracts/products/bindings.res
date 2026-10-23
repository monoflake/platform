/**
 * A binding's token made by its control and taken by its host, RFCs vr5lw, 3d3nt and rxmd9. `open`
 * is the operator's, and `bind` the host's, presenting the token as a bearer.
 */
open Subset

let types: array<declared> = [
  {
    name: "binding-open",
    def: Record([field("organization", 1, Id("organization"))]),
    from: "rxmd9",
  },
  // Answered once, the token `<binding>.<secret>` as JSON writes the two, 3d3nt.
  {
    name: "binding-opened",
    def: Record([field("binding", 1, Id("capacity")), field("secret", 2, Prim(#secret))]),
    from: "3d3nt, rxmd9",
  },
  {name: "binding-bind", def: Record([]), from: "rxmd9"},
  // The private address the control reaches the host at, and the tunnel's token where the control
  // makes the host a tunnel, its text's UTF-8.
  {
    name: "binding-bound",
    def: Record([
      field("binding", 1, Id("capacity")),
      field("address", 2, Prim(#string)),
      optional("tunnel", 3, Prim(#secret)),
    ]),
    from: "rxmd9",
  },
]

/** Binding again answers the same address and tunnel, so a host restarted binds as it first did. */
let interface_: interface_ = {
  name: "bindings",
  version: 1,
  from: "rxmd9",
  operations: [
    op("open", "binding-open", "binding-opened", [("not_found", #rejected)]),
    op("bind", "binding-bind", "binding-bound", [("unreachable", #unavailable)]),
  ],
}
