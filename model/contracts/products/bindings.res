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
  // What the host is reached by, a tunnel the control makes or an origin it calls back, 8j7b0. An
  // origin is `https` on a DNS name and the default port, with nothing after its host.
  {
    name: "binding-reach",
    def: Union({
      tag: "name",
      cases: [
        {name: "tunnel", code: 1, fields: []},
        {name: "origin", code: 2, fields: [field("origin", 1, Prim(#string))]},
      ],
    }),
    from: "rxmd9, 8j7b0",
  },
  {
    name: "binding-bind",
    def: Record([field("reach", 1, Type("binding-reach"))]),
    from: "rxmd9, 8j7b0",
  },
  // The private address the control reaches a tunneled host at and the tunnel's token where it
  // makes one, its text's UTF-8, or the origin proven by its call back.
  {
    name: "binding-reached",
    def: Union({
      tag: "name",
      cases: [
        {
          name: "tunnel",
          code: 1,
          fields: [field("address", 1, Prim(#string)), optional("tunnel", 2, Prim(#secret))],
        },
        {name: "origin", code: 2, fields: [field("origin", 1, Prim(#string))]},
      ],
    }),
    from: "rxmd9, 8j7b0",
  },
  {
    name: "binding-bound",
    def: Record([
      field("binding", 1, Id("capacity")),
      field("reached", 2, Type("binding-reached")),
    ]),
    from: "rxmd9, 8j7b0",
  },
]

/**
 * Binding again answers the same address and tunnel, so a host restarted binds as it first did; an
 * origin is called back before it is kept, `not_proven` where no driver of the binding answers.
 */
let interface_: interface_ = {
  name: "bindings",
  version: 2,
  from: "rxmd9, 8j7b0",
  operations: [
    op("open", "binding-open", "binding-opened", [("not_found", #rejected)], ~callers=[#operator]),
    op(
      "bind",
      "binding-bind",
      "binding-bound",
      [("unreachable", #unavailable), ("not_proven", #rejected), ("invalid", #rejected)],
      ~callers=[#host],
    ),
  ],
}
