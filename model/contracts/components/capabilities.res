/**
 * The issuer's interface, RFCs vuanj and b8f35: capabilities asked for and signed, each call to it
 * signed by its caller's certificate, `kcwt` carrying the certificate, so what asks is proven and
 * never told. An app's capabilities are given for its grants, read from its organization's bundle;
 * a component's own, for its own work, reach its blob space alone, as `spaces` says. A scope
 * suspended is given none.
 */
open Subset

/**
 * The blob space each component's own capability reaches, by its name in the model as its
 * certificate's `sub` says, decided by the author on 2026-10-20: what the issuer reads to decide,
 * and never a certificate's role.
 */
let spaces = [
  ("storage", "storage"),
  ("compute", "compute"),
  ("database", "database"),
  ("tablet", "database"),
]

let types: array<declared> = [
  // The targets asked for, each one the app holds a grant for, or every one it holds where none
  // is named.
  {
    name: "capabilities-for-app",
    def: Record([field("app", 1, Id("app")), optional("targets", 2, List(Type("grant-target")))]),
    from: "vuanj",
  },
  // A capability signed, as a COSE Sign1, and when it expires, in seconds as its `exp`.
  {
    name: "capability-issued",
    def: Record([
      field("target", 1, Type("grant-target")),
      field("capability", 2, Prim(#bytes)),
      field("exp", 3, Prim(#uint53)),
    ]),
    from: "vuanj, b8f35",
  },
  {
    name: "capabilities-issued",
    def: Record([field("capabilities", 1, List(Type("capability-issued")))]),
    from: "vuanj",
  },
  // A component's own: the space it reaches, and the rights its work asks.
  {
    name: "capability-for-space",
    def: Record([field("space", 1, Type("blob-space")), field("rights", 2, Type("rights"))]),
    from: "vuanj, b8f35",
  },
  {
    name: "space-capability-issued",
    def: Record([field("capability", 1, Prim(#bytes)), field("exp", 2, Prim(#uint53))]),
    from: "vuanj, b8f35",
  },
]

let interface_: interface_ = {
  name: "issuer",
  version: 1,
  from: "vuanj, b8f35",
  operations: [
    op(
      "for_app",
      "capabilities-for-app",
      "capabilities-issued",
      [("not_granted", #rejected), ("suspended", #rejected)],
    ),
    op(
      "for_space",
      "capability-for-space",
      "space-capability-issued",
      [("not_permitted", #rejected), ("suspended", #rejected)],
    ),
  ],
}
