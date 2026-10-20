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
        {name: "secret", code: 2, fields: [field("sealed", 1, Prim(#bytes))]},
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
]

let contents: array<content> = [{half: #organization, kind: "app", version: 1, content: "app"}]
