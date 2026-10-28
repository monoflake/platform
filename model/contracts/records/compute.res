/** The compute product's record, an app's, RFC 49qyg. */
open Subset

let types: array<declared> = [
  {
    name: "app-ingress",
    def: Union({
      tag: "name",
      cases: [
        {name: "domain", code: 1, fields: [field("domain", 1, Prim(#string))]},
        {name: "mount", code: 2, fields: [field("scope", 1, Prim(#string))]},
        {name: "binding", code: 3, fields: []},
      ],
    }),
    from: "oomwh",
  },
  // An env key's value, a config's as written or a secret's sealed under its control's key, v7v3w.
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
  // A build's manifest, found by its version's hash where its builder keeps it, vr5lw. Its types
  // are the WIT it carries, checked by the wit library, 49qyg.
  {
    name: "function-kind",
    def: Enum({choices: codes(["derive", "effect"]), ordered: false}),
    from: "49qyg",
  },
  // A function of its WIT, its kind and what it needs, each a capability's value by its name.
  {
    name: "manifest-function",
    def: Record([
      field("name", 1, Prim(#string)),
      field("kind", 2, Type("function-kind")),
      optional("needs", 3, Map(Type("allowance-value"))),
    ]),
    from: "49qyg",
  },
  // How far an export is shown, within its organization by default or to anyone, vr5lw.
  {
    name: "export-shown",
    def: Enum({choices: codes(["organization", "public"]), ordered: false}),
    from: "49qyg, vr5lw",
  },
  {
    name: "manifest-export",
    def: Record([field("function", 1, Prim(#string)), optional("shown", 2, Type("export-shown"))]),
    from: "49qyg",
  },
  // A call to another app's export, through the slot of type `app` its owner fills.
  {
    name: "manifest-call",
    def: Record([field("slot", 1, Prim(#string)), field("function", 2, Prim(#string))]),
    from: "49qyg",
  },
  {
    name: "slot-type",
    def: Enum({
      choices: codes(["app", "database", "file_bucket", "object_bucket"]),
      ordered: false,
    }),
    from: "49qyg",
  },
  {
    name: "manifest-slot",
    def: Record([field("name", 1, Prim(#string)), field("type", 2, Type("slot-type"))]),
    from: "49qyg",
  },
  {
    name: "env-kind",
    def: Enum({choices: codes(["config", "secret"]), ordered: false}),
    from: "49qyg",
  },
  {
    name: "manifest-env",
    def: Record([field("key", 1, Prim(#string)), field("kind", 2, Type("env-kind"))]),
    from: "49qyg",
  },
  // A schedule's times, five fields of cron's in UTC, as Cloudflare's triggers take them.
  {
    name: "manifest-schedule",
    def: Record([field("function", 1, Prim(#string)), field("cron", 2, Prim(#string))]),
    from: "49qyg",
  },
  // What a queue's failure does, the message dropped or tried again so many times, so far apart.
  {
    name: "queue-failure",
    def: Union({
      tag: "name",
      cases: [
        {name: "drop", code: 1, fields: []},
        {
          name: "retry",
          code: 2,
          fields: [field("tries", 1, Prim(#uint32)), field("spacing", 2, Prim(#uint53))],
        },
      ],
    }),
    from: "49qyg",
  },
  {
    name: "manifest-queue",
    def: Record([
      field("name", 1, Prim(#string)),
      field("function", 2, Prim(#string)),
      field("failure", 3, Type("queue-failure")),
    ]),
    from: "49qyg",
  },
  // A database slot's migrations, run in the order of their names, each once, as D1 runs them, the
  // ones run kept in the database itself, zn3u5.
  {
    name: "migration",
    def: Record([field("name", 1, Prim(#string)), field("sql", 2, Prim(#string))]),
    from: "zn3u5",
  },
  {
    name: "manifest-migrations",
    def: Record([field("slot", 1, Prim(#string)), field("migrations", 2, List(Type("migration")))]),
    from: "zn3u5",
  },
  // A daemon's shape is open, so no manifest declares one yet [C11].
  {
    name: "manifest",
    def: Record([
      field("wit", 1, Prim(#string)),
      field("functions", 2, List(Type("manifest-function"))),
      optional("exports", 3, List(Type("manifest-export"))),
      optional("calls", 4, List(Type("manifest-call"))),
      optional("slots", 5, List(Type("manifest-slot"))),
      optional("env", 6, List(Type("manifest-env"))),
      optional("schedules", 7, List(Type("manifest-schedule"))),
      optional("queues", 8, List(Type("manifest-queue"))),
      optional("migrations", 9, List(Type("manifest-migrations"))),
    ]),
    from: "49qyg, vr5lw, zn3u5",
  },
  // `version` is the hash of the build deployed, whose manifest it finds; nothing here makes the
  // app public, which a mount or a name does, vr5lw.
  {
    name: "app",
    def: Record([
      field("version", 1, Prim(#hash)),
      field("bindings", 2, Type("app-bindings")),
      field("env", 3, Map(Type("app-env"))),
    ]),
    from: "49qyg",
  },
  // An app as its bundle holds it, its record but its env and the hosts its deployment was placed
  // on, vr5lw.
  {
    name: "bundle-app",
    def: Record([
      field("version", 1, Prim(#hash)),
      field("bindings", 2, Type("app-bindings")),
      field("hosts", 3, List(Id("extension"))),
    ]),
    from: "49qyg, vr5lw",
  },
  // The compute's section of a bundle, each app by its id.
  {
    name: "bundle-compute",
    def: Record([field("apps", 1, Map(Type("bundle-app")))]),
    from: "vuanj",
  },
]

let contents: array<content> = [{half: #organization, kind: "app", version: 2, content: "app"}]
