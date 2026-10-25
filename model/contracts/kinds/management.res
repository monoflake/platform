/**
 * A driver's management, a list of capacity sent whole by generation, a grace policy and `end`,
 * every call carrying the binding token, RFC vr5lw.
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
  // An item is a `capacity` record the driver diffs by its id. Each credential is the BLAKE3 of 32
  // random bytes the control made.
  {
    name: "management-item",
    def: Record([
      field("id", 1, Id("capacity")),
      field("capacity", 2, Type("management-capacity")),
      field("credentials", 3, List(Prim(#hash))),
    ]),
    from: "vr5lw",
  },
  // A kind a binding offers, chosen as its driver is installed, vbg0u.
  {
    name: "management-kind",
    def: Enum({
      choices: [
        {name: "function", code: 1},
        {name: "instance", code: 2},
        {name: "container", code: 3},
        {name: "object", code: 4},
        {name: "volume", code: 5},
        {name: "database", code: 6},
      ],
      ordered: false,
    }),
    from: "vbg0u",
  },
  // A kind whose resource an organization's admin may list as the driver's own, vbg0u.
  {
    name: "management-adoptable",
    def: Enum({
      choices: [
        {name: "function", code: 1},
        {name: "object", code: 2},
        {name: "database", code: 3},
      ],
      ordered: false,
    }),
    from: "vbg0u",
  },
  // What an adopted resource stands for, a deployment as the deployments interface names it, or a
  // management item by its id.
  {
    name: "management-adopted-for",
    def: Union({
      tag: "name",
      cases: [
        {name: "deployment", code: 1, fields: [field("runs", 1, Type("deployment-runs"))]},
        {name: "item", code: 2, fields: [field("id", 1, Id("capacity"))]},
      ],
    }),
    from: "vbg0u",
  },
  // A resource on the bound host by its exact name, never a pattern, which the driver manages as
  // its own and only ever updates, never deletes, nrs5v and vbg0u.
  {
    name: "management-adopted",
    def: Record([
      field("kind", 1, Type("management-adoptable")),
      field("name", 2, Prim(#string)),
      field("for", 3, Type("management-adopted-for")),
    ]),
    from: "vbg0u",
  },
  // What a person should act on, `delete_by_hand` a listed resource released, named, kept until it
  // no longer exists, vbg0u.
  {
    name: "management-warning",
    def: Record([
      field("reason", 1, Prim(#string)),
      field("message", 2, Prim(#string)),
      field("name", 3, Prim(#string)),
    ]),
    from: "vbg0u",
  },
  // `tokens`, where given, are the binding's tokens still in force by their BLAKE3, and the driver
  // forgets every other it holds, 3d3nt. `adopted` is the exception list, vbg0u.
  {
    name: "management-apply",
    def: Record([
      field("generation", 1, Prim(#uint53)),
      field("items", 2, List(Type("management-item"))),
      optional("tokens", 3, List(Prim(#hash))),
      optional("adopted", 4, List(Type("management-adopted"))),
    ]),
    from: "vr5lw, 3d3nt, vbg0u",
  },
  // The generation the driver holds, the one sent or a newer it took before.
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
  // What the driver holds and the git revision it was built from, absent where it was given none,
  // wnqvu. Use reported is open [C18]. `kinds` absent is every kind the model gives that driver.
  {
    name: "management-described",
    def: Record([
      field("generation", 1, Prim(#uint53)),
      field("policy", 2, Prim(#uint53)),
      field("grace", 3, Prim(#uint32)),
      field("items", 4, List(Type("management-holding"))),
      optional("revision", 5, Prim(#string)),
      optional("kinds", 6, List(Type("management-kind"))),
      optional("adopted", 7, List(Type("management-adopted"))),
      optional("warnings", 8, List(Type("management-warning"))),
    ]),
    from: "vr5lw, vbg0u",
  },
  {name: "management-end", def: Record([field("id", 1, Id("capacity"))]), from: "vr5lw"},
  {name: "management-ended", def: Record([]), from: "vr5lw"},
]

/**
 * Ending what is not there succeeds; what the list still asks is ended only by a list without it.
 */
let interface_: interface_ = {
  name: "management",
  version: 3,
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
