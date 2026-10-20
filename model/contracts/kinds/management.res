/**
 * A driver's management, RFC vr5lw: what a binding asks is a list of capacity, sent whole and
 * numbered by generation; a policy, the grace, with a generation of its own; and `end`, the one
 * command apart from them. Every call carries the binding token. Function and instance are never
 * in the list: they are deployed into what it holds, by compute's interface.
 */
open Subset

let types: array<declared> = [
  // Cores in thousandths, and every size in bytes.
  {
    name: "management-capacity",
    def: Union({
      tag: "name",
      cases: [
        {
          name: "container",
          code: 1,
          fields: [field("millicores", 1, Prim(#uint32)), field("memory", 2, Prim(#uint53))],
        },
        {name: "volume", code: 2, fields: [field("size", 1, Prim(#uint53))]},
        {name: "object", code: 3, fields: [field("size", 1, Prim(#uint53))]},
        {name: "database", code: 4, fields: [field("size", 1, Prim(#uint53))]},
      ],
    }),
    from: "vr5lw",
  },
  // An item is a `capacity` record, so the driver diffs by its id, which is never renamed. Each
  // credential is the BLAKE3 of a random secret of 32 bytes the control
  // made, which needs no salt; two while one replaces the other, and the driver makes none.
  {
    name: "management-item",
    def: Record([
      field("id", 1, Id("capacity")),
      field("capacity", 2, Type("management-capacity")),
      field("credentials", 3, List(Prim(#hash))),
    ]),
    from: "vr5lw",
  },
  {
    name: "management-apply",
    def: Record([
      field("generation", 1, Prim(#uint53)),
      field("items", 2, List(Type("management-item"))),
    ]),
    from: "vr5lw",
  },
  // The generation the driver holds: the one sent, or a newer it took before, the older dropped.
  {name: "management-held", def: Record([field("generation", 1, Prim(#uint53))]), from: "vr5lw"},
  // The grace in whole seconds, 0 removing at once, at most a year.
  {
    name: "management-policy",
    def: Record([field("generation", 1, Prim(#uint53)), field("grace", 2, Prim(#uint32))]),
    from: "vr5lw",
  },
  {name: "management-describe", def: Record([]), from: "vr5lw"},
  // `since` is when the driver first found the item unasked, in milliseconds; it is removed once
  // the grace has passed after.
  {
    name: "management-state",
    def: Union({
      tag: "name",
      cases: [
        {name: "making", code: 1, fields: []},
        {name: "made", code: 2, fields: [field("address", 1, Prim(#string))]},
        {
          name: "failed",
          code: 3,
          fields: [field("reason", 1, Prim(#string)), optional("message", 2, Prim(#string))],
        },
        {
          name: "unasked",
          code: 4,
          fields: [field("since", 1, Prim(#uint53)), optional("address", 2, Prim(#string))],
        },
      ],
    }),
    from: "vr5lw",
  },
  {
    name: "management-holding",
    def: Record([
      field("id", 1, Id("capacity")),
      field("capacity", 2, Type("management-capacity")),
      field("state", 3, Type("management-state")),
    ]),
    from: "vr5lw",
  },
  // What the driver holds: the list's and the policy's generations, the grace, and each item. What
  // it reports of use is open [C18], to come as an optional field.
  {
    name: "management-described",
    def: Record([
      field("generation", 1, Prim(#uint53)),
      field("policy", 2, Prim(#uint53)),
      field("grace", 3, Prim(#uint32)),
      field("items", 4, List(Type("management-holding"))),
    ]),
    from: "vr5lw",
  },
  {name: "management-end", def: Record([field("id", 1, Id("capacity"))]), from: "vr5lw"},
  {name: "management-ended", def: Record([]), from: "vr5lw"},
]

/** Ending what is not there succeeds; what the list still asks is ended only by a list without it. */
let interface_: interface_ = {
  name: "management",
  version: 2,
  from: "vr5lw",
  operations: [
    op(
      "apply",
      "management-apply",
      "management-held",
      [("beyond_host", #rejected), ("invalid", #rejected)],
    ),
    op("set_policy", "management-policy", "management-held", [("invalid", #rejected)]),
    op("describe", "management-describe", "management-described", []),
    op("end", "management-end", "management-ended", [("still_asked", #rejected)]),
  ],
}
