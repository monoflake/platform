/**
 * The compute kinds' contract, RFC vr5lw: function, instance and container are each deployed by
 * this one interface, into what a driver's list holds already, and differ in how what is deployed
 * is called, which is an app's own exports in WIT, never this subset. A deployment is of an app, by
 * its id, or of a component of the platform's own, by the name the model gives it; neither is
 * renamed.
 */
open Subset

let types: array<declared> = [
  // What a builder makes: a bundle of JavaScript modules, a WebAssembly component, an OCI image
  // [C11].
  {
    name: "deployment-form",
    def: Enum({choices: codes(["modules", "component", "image"]), ordered: false}),
    from: "vr5lw",
  },
  // What runs a form: Cloudflare's Workers runtime and workerd for modules, wasmtime for a
  // component, an OCI runtime for an image. Each driver declares its own,
  // `model/ground/drivers.res`.
  {
    name: "deployment-runtime",
    def: Enum({
      choices: codes(["workers", "workerd", "wasmtime", "runc", "crun", "youki"]),
      ordered: false,
    }),
    from: "vr5lw",
  },
  // What keeps a deployment apart, each standing on its own and none above another: an isolate
  // within its process; the kernel's namespaces and cgroups; a kernel in user space; a virtual
  // machine.
  {
    name: "deployment-isolation",
    def: Enum({choices: codes(["isolate", "kernel", "userspace", "vm"]), ordered: false}),
    from: "vr5lw",
  },
  {
    name: "deployment-network",
    def: Enum({choices: codes(["http", "tcp", "udp", "icmp"]), ordered: false}),
    from: "49qyg",
  },
  {
    name: "deployment-runs",
    def: Union({
      tag: "name",
      cases: [
        {name: "app", code: 1, fields: [field("id", 1, Id("app"))]},
        {name: "component", code: 2, fields: [field("component", 1, Prim(#string))]},
      ],
    }),
    from: "vr5lw",
  },
  // Where the driver fetches it from, an address its builder gave, and its hash, checked.
  {
    name: "deployment-artifact",
    def: Record([field("address", 1, Prim(#string)), field("hash", 2, Prim(#hash))]),
    from: "vr5lw",
  },
  // Deploying is idempotent: what runs is this version, sent again the same. The runtime is the
  // driver's to choose unless set, among those that take the form and stand on every isolation
  // asked. A secret is deployed here alone, never in a bundle, and never answered, v7v3w; the rest
  // the deployment reads from its bundle, at the footing named. `into` is the container of the
  // list it runs in, on a machine; `port`, an image's, is where it is called.
  {
    name: "deployment-deploy",
    def: Record([
      field("runs", 1, Type("deployment-runs")),
      field("version", 2, Prim(#hash)),
      field("form", 3, Type("deployment-form")),
      optional("runtime", 4, Type("deployment-runtime")),
      field("isolation", 5, List(Type("deployment-isolation"))),
      field("artifact", 6, Type("deployment-artifact")),
      field("footing", 7, Prim(#string)),
      field("secrets", 8, Map(Prim(#secret))),
      field("network", 9, List(Type("deployment-network"))),
      optional("into", 10, Id("capacity")),
      optional("port", 11, Prim(#uint32)),
    ]),
    from: "vr5lw, v7v3w, 49qyg",
  },
  {name: "deployment-of", def: Record([field("runs", 1, Type("deployment-runs"))]), from: "vr5lw"},
  // `running` names the runtime chosen and every isolation it stands on.
  {
    name: "deployment-state",
    def: Union({
      tag: "name",
      cases: [
        {name: "making", code: 1, fields: []},
        {
          name: "running",
          code: 2,
          fields: [
            field("address", 1, Prim(#string)),
            field("runtime", 2, Type("deployment-runtime")),
            field("isolation", 3, List(Type("deployment-isolation"))),
          ],
        },
        {name: "stopped", code: 3, fields: []},
        {
          name: "failed",
          code: 4,
          fields: [field("reason", 1, Prim(#string)), optional("message", 2, Prim(#string))],
        },
      ],
    }),
    from: "vr5lw",
  },
  {
    name: "deployment-described",
    def: Record([
      field("runs", 1, Type("deployment-runs")),
      field("version", 2, Prim(#hash)),
      field("state", 3, Type("deployment-state")),
    ]),
    from: "vr5lw",
  },
  {name: "deployment-deleted", def: Record([]), from: "vr5lw"},
]

/**
 * Stopping, resuming and describing what was never deployed fail as `not_found`; deleting it
 * succeeds.
 */
let interface_: interface_ = {
  name: "deployments",
  version: 2,
  declared: ["artifact"],
  from: "vr5lw",
  operations: [
    op(
      "deploy",
      "deployment-deploy",
      "deployment-described",
      [
        ("beyond_host", #rejected),
        ("too_large", #rejected),
        ("hash_mismatch", #rejected),
        ("unfetchable", #unavailable),
      ],
    ),
    op("stop", "deployment-of", "deployment-described", [("not_found", #rejected)]),
    op("resume", "deployment-of", "deployment-described", [("not_found", #rejected)]),
    op("describe", "deployment-of", "deployment-described", [("not_found", #rejected)]),
    op("delete", "deployment-of", "deployment-deleted", [("still_running", #rejected)]),
  ],
}
