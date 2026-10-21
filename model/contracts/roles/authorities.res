/**
 * The authority's contract, RFC 7xpd3, both its ends: what an organization's control pulls of the
 * role above it and asks it to certify, each call signed by the organization's own key, and the
 * notice the authority sends that there is something to pull, unsigned, which the control gives.
 * What is pulled is one record the authority signs, its generation never below the one the control
 * holds, so an old record is never taken back. The roles' contracts are named for what they carry,
 * in the plural.
 */
open Subset

let types: array<declared> = [
  // What an organization binds of another's, as it crosses, known by its host, no secret in it; what
  // binding it asks past these waits on C3.
  {
    name: "authority-loan",
    def: Record([
      field("host", 1, Type("extension-host")),
      field("endpoint", 2, Prim(#string)),
      field("levels", 3, Type("placement")),
      field("place", 4, Type("extension-place")),
      field("quota", 5, Prim(#uint53)),
      field("address", 6, Prim(#bool)),
    ]),
    from: "7xpd3, v7v3w",
  },
  // The record pulled, signed by the authority: its generation, the organization's certificate as
  // signed, its allowance, what it is lent and its status.
  {
    name: "authority-record",
    def: Record([
      field("generation", 1, Prim(#uint53)),
      field("certificate", 2, Prim(#bytes)),
      field("allowance", 3, Map(Type("allowance-value"))),
      field("loans", 4, List(Type("authority-loan"))),
      field("status", 5, Type("scope-status")),
    ]),
    from: "7xpd3",
  },
  // The generation the control holds, none where it holds nothing yet.
  {
    name: "authority-pull",
    def: Record([optional("holding", 1, Prim(#uint53))]),
    from: "7xpd3",
  },
  {
    name: "authority-pulled",
    def: Record([field("record", 1, Prim(#bytes))]),
    from: "7xpd3",
  },
  // A working key to certify, and what it signs: the issuer's capabilities, or the bundle.
  {
    name: "authority-certify",
    def: Record([
      field("key", 1, Type("confirmation")),
      field("role", 2, Type("certificate-role")),
    ]),
    from: "7xpd3, b8f35",
  },
  {
    name: "authority-certified",
    def: Record([field("certificate", 1, Prim(#bytes))]),
    from: "7xpd3, b8f35",
  },
  // A notice: that there is a generation to pull, and nothing else.
  {name: "notice", def: Record([field("generation", 1, Prim(#uint53))]), from: "7xpd3"},
  {name: "noticed", def: Record([]), from: "7xpd3"},
]

/** A record whose generation is below what the control holds is never answered. */
let interface_: interface_ = {
  name: "authority",
  version: 1,
  from: "7xpd3",
  operations: [
    op("pull", "authority-pull", "authority-pulled", [("ahead", #rejected)]),
    op(
      "certify",
      "authority-certify",
      "authority-certified",
      [("role_refused", #rejected), ("suspended", #rejected)],
    ),
  ],
}

/** The control's end: a notice, repeated until the generation it names is pulled. */
let notices: interface_ = {
  name: "notices",
  version: 1,
  from: "7xpd3",
  operations: [op("notice", "notice", "noticed", [])],
}
