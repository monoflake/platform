/**
 * The records an organization's control keeps of its own, itself, its people, its tree, names,
 * mounts, extensions and capacity, RFCs v7v3w and vr5lw.
 */
open Subset

let types: array<declared> = [
  {
    name: "security",
    def: Enum({choices: codes(["default", "strict"]), ordered: false}),
    from: "v7v3w, vuanj",
  },
  // An organization's own record, its name shown, how long its credentials live, vuanj, and the
  // grace its extensions inherit, vr5lw.
  {
    name: "organization",
    def: Record([
      optional("name", 1, Prim(#string)),
      field("security", 2, Type("security")),
      optional("grace", 3, Prim(#uint32)),
    ]),
    from: "v7v3w",
  },
  {
    name: "role",
    def: Enum({choices: codes(["member", "admin"]), ordered: false}),
    from: "v7v3w",
  },
  // A member is written once its account accepts, and reported to the platform's `membership`; an
  // organization holds one admin at least, which its control holds as it writes.
  {
    name: "member",
    def: Record([
      field("account", 1, Across(#platform, "account")),
      field("role", 2, Type("role")),
    ]),
    from: "v7v3w",
  },
  // An invitation offers an account a role, and lapses seven days after the generation that wrote
  // it.
  {
    name: "invitation",
    def: Record([
      field("account", 1, Across(#platform, "account")),
      field("role", 2, Type("role")),
    ]),
    from: "v7v3w",
  },
  {
    name: "tree-type",
    def: Enum({choices: codes(["folder", "app", "database", "bucket"]), ordered: false}),
    from: "v7v3w",
  },
  // A node of the tree, its resource's or a folder's id, the folder it sits in, its `slug` in a
  // path and the `name` shown.
  {
    name: "tree",
    def: Record([
      optional("parent", 1, Id("tree")),
      field("type", 2, Type("tree-type")),
      field("slug", 3, Prim(#string)),
      field("name", 4, Prim(#string)),
    ]),
    from: "v7v3w",
  },
  {
    name: "name-target",
    def: Union({
      tag: "name",
      cases: [
        {name: "app", code: 1, fields: [field("id", 1, Id("app"))]},
        {name: "storage", code: 2, fields: []},
      ],
    }),
    from: "vr5lw",
  },
  // A domain the platform's `domain` table holds for the organization, bound to its target;
  // `preferred` where it is the storage's name that links are made at, vr5lw.
  {
    name: "name",
    def: Record([
      field("domain", 1, Prim(#string)),
      field("target", 2, Type("name-target")),
      optional("preferred", 3, Prim(#bool)),
    ]),
    from: "vr5lw",
  },
  // A mount under the organization's gateway, a scope written as a label to the app it hands
  // `/v{n}/...`, vr5lw.
  {
    name: "scope",
    def: Record([field("scope", 1, Prim(#string)), field("app", 2, Id("app"))]),
    from: "vr5lw",
  },
  {
    name: "extension-driver",
    def: Enum({choices: codes(["cloudflare", "machine"]), ordered: false}),
    from: "v7v3w",
  },
  // What is bound, the driver's kind and the host's own identifier.
  {
    name: "extension-host",
    def: Record([
      field("driver", 1, Type("extension-driver")),
      field("identifier", 2, Prim(#string)),
    ]),
    from: "v7v3w",
  },
  // Where the host declares it stands as it is bound, 13ixj.
  {
    name: "extension-place",
    def: Record([
      optional("node", 1, Prim(#string)),
      optional("site", 2, Prim(#string)),
      optional("account", 3, Prim(#string)),
      optional("zone", 4, Prim(#string)),
      optional("region", 5, Prim(#string)),
    ]),
    from: "13ixj, v7v3w",
  },
  // Who lent the extension, whose management token and shell key are the lender's and never its
  // own.
  {
    name: "extension-lender",
    def: Union({tag: "name", cases: [{name: "platform", code: 1, fields: []}]}),
    from: "v7v3w",
  },
  {
    name: "extension-relays",
    def: Union({
      tag: "name",
      cases: [
        {name: "all", code: 1, fields: []},
        {
          name: "some",
          code: 2,
          fields: [field("extensions", 1, List(Id("extension")))],
        },
      ],
    }),
    from: "v7v3w",
  },
  // A host injected from outside and bound, its management's endpoint, its sealed tokens and keys,
  // its levels, quota, grace and dismissed warnings.
  {
    name: "extension",
    def: Record([
      field("host", 1, Type("extension-host")),
      field("endpoint", 2, Prim(#string)),
      field("token", 3, Prim(#secret)),
      field("levels", 4, Type("placement")),
      field("place", 5, Type("extension-place")),
      optional("quota", 6, Prim(#uint53)),
      optional("grace", 7, Prim(#uint32)),
      field("relays", 8, Type("extension-relays")),
      field("address", 9, Prim(#bool)),
      optional("management", 10, Prim(#secret)),
      optional("shell", 11, Prim(#secret)),
      field("dismissed", 12, List(Prim(#string))),
      optional("lender", 13, Type("extension-lender")),
    ]),
    from: "v7v3w, vr5lw",
  },
  // A share opened on an extension, an item of its driver's list, its capacity and its sealed
  // secrets, whose hashes alone reach the driver, vr5lw.
  {
    name: "capacity",
    def: Record([
      field("extension", 1, Id("extension")),
      field("capacity", 2, Type("management-capacity")),
      field("credentials", 3, List(Prim(#secret))),
    ]),
    from: "vr5lw",
  },
  // The gateway's section of a bundle, every name bound and every mount as the control holds them.
  {
    name: "bundle-gateway",
    def: Record([field("names", 1, List(Type("name"))), field("scopes", 2, List(Type("scope")))]),
    from: "vr5lw",
  },
  // A host as its bundle holds it, its relays and whether it has a public address, nothing sealed.
  {
    name: "bundle-host",
    def: Record([field("relays", 1, Type("extension-relays")), field("address", 2, Prim(#bool))]),
    from: "vr5lw",
  },
  // The hosts' section of a bundle, each host by its extension's id.
  {
    name: "bundle-hosts",
    def: Record([field("hosts", 1, Map(Type("bundle-host")))]),
    from: "vr5lw",
  },
]

let contents: array<content> = [
  {half: #organization, kind: "organization", version: 1, content: "organization"},
  {half: #organization, kind: "member", version: 1, content: "member"},
  {half: #organization, kind: "invitation", version: 1, content: "invitation"},
  {
    half: #organization,
    kind: "tree",
    version: 1,
    content: "tree",
    unique: [["parent", "type", "slug"]],
  },
  {half: #organization, kind: "name", version: 1, content: "name"},
  {half: #organization, kind: "scope", version: 1, content: "scope", unique: [["scope"]]},
  {half: #organization, kind: "extension", version: 3, content: "extension"},
  {half: #organization, kind: "capacity", version: 2, content: "capacity"},
]
