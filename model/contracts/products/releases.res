/**
 * A release kept by its hash and deployed as an app onto a bound host, the operator's alone, RFC
 * rxmd9. A deploy and a describe answer what the host's driver answered, through `deployments`.
 */
open Subset

let types: array<declared> = [
  // The artifact whole, its hash the SHA-256 of these bytes, as the driver checks it, ge55b.
  {
    name: "release-put",
    def: Record([field("form", 1, Type("deployment-form")), field("artifact", 2, Prim(#bytes))]),
    from: "rxmd9, ge55b",
  },
  {
    name: "release-held",
    def: Record([field("hash", 1, Prim(#hash)), field("size", 2, Prim(#uint53))]),
    from: "rxmd9",
  },
  // An app runs on one binding at a time, so deploying it onto another moves it there. Its secrets
  // and network are handed to the driver and kept by no control.
  {
    name: "release-deploy",
    def: Record([
      field("binding", 1, Id("capacity")),
      field("app", 2, Id("app")),
      field("release", 3, Prim(#hash)),
      optional("secrets", 4, Map(Prim(#secret))),
      optional("network", 5, List(Type("deployment-network"))),
    ]),
    from: "rxmd9",
  },
  {name: "release-of", def: Record([field("app", 1, Id("app"))]), from: "rxmd9"},
]

/** A host that does not answer is `unreachable`, and the caller retries, rxmd9. */
let interface_: interface_ = {
  name: "releases",
  version: 1,
  bounds: dict{"artifact": 33554432},
  from: "rxmd9",
  operations: [
    op("put", "release-put", "release-held", [("too_large", #rejected)], ~callers=[#operator]),
    op(
      "deploy",
      "release-deploy",
      "deployment-described",
      [
        ("not_found", #rejected),
        ("unbound", #rejected),
        ("invalid", #rejected),
        ("beyond_host", #rejected),
        ("too_large", #rejected),
        ("hash_mismatch", #rejected),
        ("unfetchable", #unavailable),
        ("unreachable", #unavailable),
      ],
      ~callers=[#operator],
    ),
    op(
      "describe",
      "release-of",
      "deployment-described",
      [("not_found", #rejected), ("unreachable", #unavailable)],
      ~callers=[#operator],
    ),
  ],
}
