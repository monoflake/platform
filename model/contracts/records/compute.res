/** The compute product's record, an app's, RFC 49qyg. */
open Subset

let types: array<declared> = [
  // An env key's value: a config's as written, a secret's sealed under its control's key, v7v3w.
  {
    name: "app-env",
    def: Union({
      tag: "name",
      cases: [
        {name: "config", code: 1, fields: [field("value", 1, Prim(#string))]},
        {name: "secret", code: 2, fields: [field("sealed", 1, Prim(#secret))]},
      ],
    }),
    from: "49qyg, v7v3w",
  },
  // What fills the slots its build declares, nested by the type of what each holds, a slot's name
  // to an id; a deployment is refused where the slot's type, this type and the id's disagree.
  {
    name: "app-bindings",
    def: Record([
      optional("app", 1, Map(Id("app"))),
      optional("database", 2, Map(Id("database"))),
      optional("bucket", 3, Map(Id("bucket"))),
    ]),
    from: "49qyg",
  },
  // `version` is the hash of the build deployed, whose manifest it finds; nothing here makes the app
  // public, which a mount or a name does, vr5lw.
  {
    name: "app",
    def: Record([
      field("version", 1, Prim(#hash)),
      field("bindings", 2, Type("app-bindings")),
      field("env", 3, Map(Type("app-env"))),
    ]),
    from: "49qyg",
  },
  // An app as its bundle holds it: its record but its env, whose secrets reach its deployment
  // alone; and the hosts its deployment was placed on, compiled as configuration is applied, vr5lw.
  {
    name: "bundle-app",
    def: Record([
      field("version", 1, Prim(#hash)),
      field("bindings", 2, Type("app-bindings")),
      field("hosts", 3, List(Id("extension"))),
    ]),
    from: "49qyg, vr5lw",
  },
  // The compute's section of a bundle: each app by its id.
  {
    name: "bundle-compute",
    def: Record([field("apps", 1, Map(Type("bundle-app")))]),
    from: "vuanj",
  },
]

let contents: array<content> = [{half: #organization, kind: "app", version: 2, content: "app"}]
