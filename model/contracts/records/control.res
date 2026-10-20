/**
 * The records an organization's control keeps of its own, RFCs v7v3w and vr5lw: the tree its
 * resources are shown on, the names bound to them, the gateway's mounts, the extensions it binds
 * and the capacity it opens on them. Every value sealed is sealed under a key deployed as a secret
 * of the control's own deployment, v7v3w.
 */
open Subset

let types: array<declared> = [
  {
    name: "tree-type",
    def: Enum({choices: codes(["folder", "app", "database", "bucket"]), ordered: false}),
    from: "v7v3w",
  },
  // A node's id is its resource's, or a folder's, from the one space; `parent` the folder it sits
  // in, none at the top; `slug` its part of a path, written as a label is; `name` the name shown, written as an account's
  // is and repeated as freely.
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
  // A mount under the organization's gateway: a scope, written as a label is and never one the
  // platform reserves, to the app it hands `/v{n}/...`, vr5lw.
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
  // What is bound: the driver's kind, and the host's own identifier, an account's id or what a
  // machine's driver reports.
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
  {
    name: "extension-relays",
    def: Union({
      tag: "name",
      cases: [
        {name: "all", code: 1, fields: []},
        {
          name: "some",
          code: 2,
          fields: [field("extensions", 1, List(Id("extension(organization)")))],
        },
      ],
    }),
    from: "v7v3w",
  },
  // A host injected from outside and bound: `endpoint` where its driver's management answers;
  // `token` the binding token, sealed; `levels` copied from the host as it is bound, its own from
  // then; `quota` none unless set; `grace` the organization's unless set; `address` whether its host
  // is declared to have a public one, which a relay dialing back checks; a management token and a
  // shell key's private half sealed, if given; and the warnings its admin dismissed.
  {
    name: "extension",
    def: Record([
      field("host", 1, Type("extension-host")),
      field("endpoint", 2, Prim(#string)),
      field("token", 3, Prim(#bytes)),
      field("levels", 4, Type("placement")),
      field("place", 5, Type("extension-place")),
      optional("quota", 6, Prim(#uint53)),
      optional("grace", 7, Prim(#uint32)),
      field("relays", 8, Type("extension-relays")),
      field("address", 9, Prim(#bool)),
      optional("management", 10, Prim(#bytes)),
      optional("shell", 11, Prim(#bytes)),
      field("dismissed", 12, List(Prim(#string))),
    ]),
    from: "v7v3w, vr5lw",
  },
  // A share opened on an extension, bound to it, an item of its driver's list: its capacity, and its
  // secrets, one or two, sealed, which the control hands what uses it and whose hashes alone it
  // sends the driver, vr5lw.
  {
    name: "capacity",
    def: Record([
      field("extension", 1, Id("extension(organization)")),
      field("capacity", 2, Type("management-capacity")),
      field("credentials", 3, List(Prim(#bytes))),
    ]),
    from: "vr5lw",
  },
]

let contents: array<content> = [
  {kind: "tree", version: 1, content: "tree"},
  {kind: "name", version: 1, content: "name"},
  {kind: "scope", version: 1, content: "scope"},
  {kind: "extension(organization)", version: 1, content: "extension"},
  {kind: "capacity", version: 1, content: "capacity"},
]
