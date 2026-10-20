/** The storage's contracts, RFC 13ixj. */
open Subset

let types: array<declared> = [
  {
    name: "bucket-type",
    def: Enum({choices: codes(["file", "object"]), ordered: false}),
    from: "13ixj",
  },
  {
    name: "availability",
    def: Enum({
      choices: codes([
        "opportunistic",
        "best_effort",
        "stable",
        "recoverable",
        "redundant",
        "multiregion",
      ]),
      ordered: true,
    }),
    from: "13ixj",
  },
  {
    name: "durability",
    def: Enum({
      choices: codes([
        "ephemeral",
        "persistent",
        "redundant",
        "replicated",
        "multizone",
        "multiregion",
      ]),
      ordered: true,
    }),
    from: "13ixj",
  },
  // Custody's codes are 0 and 1, compared as integers, though it is no ordered level, 13ixj.
  {
    name: "custody",
    def: Enum({choices: [{name: "false", code: 0}, {name: "true", code: 1}], ordered: false}),
    from: "13ixj",
  },
  {
    name: "placement",
    def: Record([
      field("availability", 1, Type("availability")),
      field("durability", 2, Type("durability")),
      field("custody", 3, Type("custody")),
    ]),
    from: "13ixj",
  },
  // How many copies at least lie in different ones of each domain, none more than `copies`.
  {
    name: "distinct",
    def: Record([
      optional("node", 1, Prim(#uint32)),
      optional("site", 2, Prim(#uint32)),
      optional("account", 3, Prim(#uint32)),
      optional("zone", 4, Prim(#uint32)),
      optional("region", 5, Prim(#uint32)),
    ]),
    from: "13ixj",
  },
  {
    name: "spread",
    def: Record([field("copies", 1, Prim(#uint32)), field("distinct", 2, Type("distinct"))]),
    from: "13ixj",
  },
  // A packed bucket is compressed and sealed unless either is set false; an opaque one is neither.
  {
    name: "bucket-kind",
    def: Union({
      tag: "name",
      cases: [
        {
          name: "packed",
          code: 1,
          fields: [optional("compress", 1, Prim(#bool)), optional("seal", 2, Prim(#bool))],
        },
        {name: "opaque", code: 2, fields: []},
      ],
    }),
    from: "13ixj",
  },
  {
    name: "access",
    def: Enum({choices: codes(["private", "public"]), ordered: false}),
    from: "13ixj",
  },
  // A bucket holds no name: it is its id, shown by its organization's tree, v7v3w. Its type is fixed
  // as it is made; its quota, in bytes, is none unless set; the apps it is bindable by are all of
  // them unless set.
  {
    name: "bucket",
    def: Record([
      field("type", 1, Type("bucket-type")),
      field("kind", 2, Type("bucket-kind")),
      field("placement", 3, Type("placement")),
      field("spread", 4, Type("spread")),
      optional("quota", 5, Prim(#uint53)),
      field("access", 6, Type("access")),
      optional("bindable", 7, List(Id("app"))),
    ]),
    from: "13ixj",
  },
]

let contents: array<content> = [{kind: "bucket", version: 1, content: "bucket"}]
